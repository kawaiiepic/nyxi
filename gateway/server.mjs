import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';

const upstreams = {
  production: 'https://graphql.klutchcard.com/graphql',
  sandbox: 'https://sandbox.klutchcard.com/graphql',
};

const SESSION = `mutation ($clientId: String, $secretKey: String) {
  createSessionToken(clientId: $clientId, secretKey: $secretKey)
}`;

const CARDS = `query {
  cards { id name status lastFour expirationDate media lockState }
}`;

const TRANSACTIONS = `query ($sortOrder: TransactionSortOrder, $limit: Int) {
  transactionsPaginated(sortOrder: $sortOrder, limit: $limit) {
    list { id transactionDate merchantName amount transactionStatus transactionType card { id } }
    nextCursor
  }
}`;

const CREATE_CARD = `mutation ($name: String, $media: CardMedia) {
  createCard(name: $name, media: $media) { id name status lastFour expirationDate media lockState }
}`;

function asObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function safeText(value, max = 128) {
  return typeof value === 'string' ? value.slice(0, max) : '';
}

function toCard(raw) {
  const card = asObject(raw);
  return {
    id: safeText(card.id),
    name: safeText(card.name),
    status: safeText(card.status),
    lastFour: safeText(card.lastFour, 4),
    expirationDate: safeText(card.expirationDate, 40),
    media: safeText(card.media),
    lockState: safeText(card.lockState),
  };
}

function toTransaction(raw) {
  const tx = asObject(raw);
  return {
    id: safeText(tx.id),
    transactionDate: safeText(tx.transactionDate, 64),
    merchantName: safeText(tx.merchantName),
    amount: typeof tx.amount === 'number' && Number.isFinite(tx.amount) ? tx.amount : 0,
    transactionStatus: safeText(tx.transactionStatus),
    transactionType: safeText(tx.transactionType),
    cardId: safeText(asObject(tx.card).id),
  };
}

function json(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(body);
}

async function bodyJson(req) {
  let size = 0;
  const parts = [];
  for await (const part of req) {
    size += part.length;
    if (size > 8192) {
      const error = new Error('Request too large');
      error.status = 413;
      throw error;
    }
    parts.push(part);
  }
  try {
    return asObject(JSON.parse(Buffer.concat(parts).toString('utf8')));
  } catch {
    const error = new Error('Invalid JSON body');
    error.status = 400;
    throw error;
  }
}

function authorize(req, key) {
  const given = req.headers.authorization;
  if (typeof given !== 'string' || !given.startsWith('Bearer ')) return false;
  const actual = Buffer.from(given.slice('Bearer '.length));
  const expected = Buffer.from(key);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function createApp({ env = process.env, fetchImpl = fetch } = {}) {
  const mode = env.KLUTCH_ENV || 'production';
  if (!(mode in upstreams)) throw new Error('KLUTCH_ENV must be production or sandbox');
  const gatewayKey = env.NYXI_GATEWAY_TOKEN || '';
  if (gatewayKey.length < 24) {
    throw new Error('NYXI_GATEWAY_TOKEN must be set to a random 24+ character secret');
  }

  let sessionToken = null;

  async function graphql(query, variables = {}, authorizeRequest = true, retry = true) {
    if (authorizeRequest && !sessionToken) {
      const session = await graphql(SESSION, {
        clientId: env.KLUTCH_CLIENT_ID,
        secretKey: env.KLUTCH_SECRET_KEY,
      }, false);
      if (typeof session.createSessionToken !== 'string' || !session.createSessionToken) {
        throw new Error('Klutch did not return a session token');
      }
      sessionToken = session.createSessionToken;
    }

    const response = await fetchImpl(upstreams[mode], {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(authorizeRequest ? { Authorization: `Bearer ${sessionToken}` } : {}),
      },
      body: JSON.stringify({ query, variables }),
      signal: AbortSignal.timeout(15000),
    });
    if (response.status === 401 && authorizeRequest && retry) {
      sessionToken = null;
      return graphql(query, variables, true, false);
    }
    if (!response.ok) {
      throw new Error(`Klutch returned HTTP ${response.status}`);
    }
    const payload = await response.json();
    if (Array.isArray(payload.errors) && payload.errors.length) {
      const message = payload.errors[0]?.message;
      throw new Error('Klutch GraphQL error: ' + safeText(message, 240));
    }
    return asObject(payload.data);
  }

  return http.createServer(async (req, res) => {
    try {
      // Only a locally started service is supported. No browser CORS allowance.
      const path = new URL(req.url || '/', 'http://localhost').pathname;
      if (req.method === 'GET' && path === '/health') {
        return json(res, 200, {
          service: 'nyxi-klutch-gateway',
          configured: Boolean(env.KLUTCH_CLIENT_ID && env.KLUTCH_SECRET_KEY),
          mode,
        });
      }
      if (!authorize(req, gatewayKey)) return json(res, 401, { error: 'Unauthorized' });
      if (!env.KLUTCH_CLIENT_ID || !env.KLUTCH_SECRET_KEY) {
        return json(res, 503, { error: 'Klutch credentials are not configured on the gateway' });
      }

      if (req.method === 'GET' && path === '/api/klutch/cards') {
        const data = await graphql(CARDS);
        return json(res, 200, { cards: Array.isArray(data.cards) ? data.cards.map(toCard) : [] });
      }
      if (req.method === 'GET' && path === '/api/klutch/transactions') {
        const data = await graphql(TRANSACTIONS, {
          sortOrder: 'UPDATED_DATE_DESC',
          limit: 30,
        });
        const page = asObject(data.transactionsPaginated);
        return json(res, 200, {
          transactions: Array.isArray(page.list) ? page.list.map(toTransaction) : [],
          hasMore: Boolean(page.nextCursor),
        });
      }
      if (req.method === 'POST' && path === '/api/klutch/cards') {
        const body = await bodyJson(req);
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        if (name.length < 2 || name.length > 60) {
          return json(res, 400, { error: 'Card name must be 2 to 60 characters' });
        }
        const data = await graphql(CREATE_CARD, { name, media: 'VIRTUAL' });
        if (!data.createCard) throw new Error('Klutch did not return a created card');
        return json(res, 201, { card: toCard(data.createCard) });
      }
      return json(res, 404, { error: 'Route not found' });
    } catch (error) {
      // Never log credentials, bearer tokens, request bodies or PAN/CVV.
      const status = Number.isInteger(error.status) ? error.status : 502;
      return json(res, status, { error: safeText(error.message || 'Provider unavailable', 280) });
    }
  });
}

if (process.argv[1] && import.meta.url === new URL('file://' + process.argv[1]).href) {
  const app = createApp();
  const port = Number(process.env.NYXI_GATEWAY_PORT || 8787);
  app.listen(port, '127.0.0.1', () => {
    console.info(`Nyxi Klutch gateway listening on http://127.0.0.1:${port} (${process.env.KLUTCH_ENV || 'production'})`);
    console.info('Loopback only. Do not expose this service to the public internet.');
  });
}
