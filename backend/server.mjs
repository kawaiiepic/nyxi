import http from 'node:http';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import {
  randomBytes, createHash, createCipheriv, createDecipheriv,
  scrypt as scryptCallback, timingSafeEqual, hkdfSync,
} from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const TTL = 7 * 24 * 60 * 60 * 1000;
const SESSION_QUERY = `mutation ($clientId: String, $secretKey: String) {
  createSessionToken(clientId: $clientId, secretKey: $secretKey)
}`;
const CARDS_QUERY = `query {
  cards { id name status lastFour expirationDate media lockState }
}`;
const TX_QUERY = `query ($limit: Int, $sortOrder: TransactionSortOrder) {
  transactionsPaginated(limit: $limit, sortOrder: $sortOrder) {
    nextCursor
    list { id merchantName transactionDate amount transactionType transactionStatus card { id } }
  }
}`;
// Klutch's documented Account -> Get Balance request.
const CREDIT_BALANCE_QUERY = `query {
  account { revolvingLoan { balance limit } }
}`;
// Authoritative month-to-date spending, not a sum of the truncated
// recent-transactions page. Klutch documents sumTransactions + TransactionFilter.
const MONTH_SPEND_QUERY = `query($filter: TransactionFilter) {
  sumTransactions(filter: $filter)
}`;
const CREATE_CARD = `mutation ($name: String, $media: CardMedia) {
  createCard(name: $name, media: $media) {
    id name status lastFour expirationDate media
  }
}`;
const URLS = Object.freeze({
  production: 'https://graphql.klutchcard.com/graphql',
  sandbox: 'https://sandbox.klutchcard.com/graphql',
});
const string = (value, limit = 128) => typeof value === 'string' ? value.slice(0, limit) : '';
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const sha = value => createHash('sha256').update(value).digest('hex');
const nowMs = () => Date.now();
const randomId = () => randomBytes(16).toString('hex');
const emailValid = value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
class ProviderError extends HttpError {
  constructor() { super(502, 'Klutch is unavailable or did not accept the request.'); }
}
const json = (res, status, data, origin = '') => {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    'Pragma': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    ...(origin ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' } : {}),
  });
  res.end(body);
};
async function readBody(req) {
  if (req.headers['content-type']?.split(';')[0] !== 'application/json') {
    throw new HttpError(415, 'Expected application/json.');
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 8192) throw new HttpError(413, 'Request too large.');
    chunks.push(chunk);
  }
  try {
    return object(JSON.parse(Buffer.concat(chunks).toString('utf8')));
  } catch {
    throw new HttpError(400, 'Invalid JSON.');
  }
}

function safeCard(value) {
  const c = object(value);
  return {
    id: string(c.id), name: string(c.name), status: string(c.status),
    lastFour: string(c.lastFour, 4), expirationDate: string(c.expirationDate, 32),
    media: string(c.media), lockState: string(c.lockState),
  };
}
function safeTransaction(value) {
  const t = object(value);
  return {
    id: string(t.id), merchantName: string(t.merchantName),
    transactionDate: string(t.transactionDate, 40),
    amount: typeof t.amount === 'number' && Number.isFinite(t.amount) ? t.amount : 0,
    transactionType: string(t.transactionType),
    transactionStatus: string(t.transactionStatus),
    cardId: string(object(t.card).id),
  };
}

export function createNyxiServer({
  env = process.env, fetchImpl = fetch, dbPath, clock = nowMs,
} = {}) {
  const key = env.NYXI_ENCRYPTION_KEY || '';
  if (!/^[0-9a-fA-F]{64}$/.test(key)) {
    throw new Error('NYXI_ENCRYPTION_KEY must be exactly 64 hexadecimal characters.');
  }
  const masterKey = Buffer.from(key, 'hex');
  const path = dbPath || env.NYXI_DB_PATH || './.data/nyxi.sqlite';
  const resolvedPath = resolve(path);
  mkdirSync(dirname(resolvedPath), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(resolvedPath);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE,
      password_salt TEXT NOT NULL, password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS klutch_connections (
      user_id TEXT PRIMARY KEY, client_enc TEXT NOT NULL,
      secret_enc TEXT NOT NULL, environment TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS card_requests (
      user_id TEXT NOT NULL, request_key TEXT NOT NULL,
      created_at INTEGER NOT NULL, state TEXT NOT NULL,
      response TEXT,
      PRIMARY KEY (user_id, request_key),
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON sessions(expires_at);
  `);

  function encrypt(value, userId) {
    const iv = randomBytes(12);
    const dataKey = Buffer.from(hkdfSync('sha256', masterKey,
      Buffer.from(userId), Buffer.from('nyxi-klutch-v1'), 32));
    const cipher = createCipheriv('aes-256-gcm', dataKey, iv);
    cipher.setAAD(Buffer.from(userId));
    const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    const result = [iv, cipher.getAuthTag(), ciphertext].map(b => b.toString('base64')).join('.');
    dataKey.fill(0);
    return result;
  }
  function decrypt(value, userId) {
    const [iv, tag, ciphertext] = value.split('.').map(v => Buffer.from(v, 'base64'));
    const dataKey = Buffer.from(hkdfSync('sha256', masterKey,
      Buffer.from(userId), Buffer.from('nyxi-klutch-v1'), 32));
    try {
      const decipher = createDecipheriv('aes-256-gcm', dataKey, iv);
      decipher.setAAD(Buffer.from(userId));
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
    } finally { dataKey.fill(0); }
  }

  async function passwordHash(password, salt) {
    return (await scrypt(password, Buffer.from(salt, 'hex'), 64, {
      N: 16384, r: 8, p: 1, maxmem: 32 * 1024 * 1024,
    })).toString('hex');
  }
  function createSession(user) {
    const token = randomBytes(32).toString('base64url');
    db.prepare('INSERT INTO sessions (token_hash,user_id,expires_at) VALUES (?,?,?)')
      .run(sha(token), user.id, clock() + TTL);
    db.prepare('DELETE FROM sessions WHERE expires_at <= ?').run(clock());
    return { token, user: { id: user.id, email: user.email }, expiresAt: clock() + TTL };
  }
  function getUser(req) {
    const auth = req.headers.authorization;
    if (typeof auth !== 'string' || !auth.startsWith('Bearer ')) {
      throw new HttpError(401, 'Sign in to Nyxi first.');
    }
    const token = auth.slice(7);
    if (token.length < 32 || token.length > 256) {
      throw new HttpError(401, 'Session expired or invalid.');
    }
    const user = db.prepare(`SELECT users.id,users.email FROM sessions
      JOIN users ON users.id = sessions.user_id
      WHERE token_hash = ? AND expires_at > ?`).get(sha(token), clock());
    if (!user) throw new HttpError(401, 'Session expired or invalid.');
    return user;
  }
  function connection(userId) {
    return db.prepare('SELECT * FROM klutch_connections WHERE user_id = ?').get(userId);
  }
  async function graphql(environment, query, variables = {}, accessToken = '') {
    try {
      const response = await fetchImpl(URLS[environment], {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(accessToken ? { Authorization: 'Bearer ' + accessToken } : {}),
        },
        body: JSON.stringify({ query, variables }),
        signal: AbortSignal.timeout(12000),
      });
      if (!response.ok) throw new ProviderError();
      const payload = await response.json();
      if (payload.errors?.length || !payload.data) throw new ProviderError();
      return object(payload.data);
    } catch {
      throw new ProviderError();
    }
  }
  const tokenCache = new Map();
  async function sessionFor(userId, row, force = false) {
    const cached = tokenCache.get(userId);
    if (!force && cached && cached.expiresAt > clock()) return cached.token;
    const clientId = decrypt(row.client_enc, userId);
    const secretKey = decrypt(row.secret_enc, userId);
    const data = await graphql(row.environment, SESSION_QUERY, { clientId, secretKey });
    if (!data.createSessionToken || typeof data.createSessionToken !== 'string') {
      throw new ProviderError();
    }
    const token = data.createSessionToken;
    tokenCache.set(userId, { token, expiresAt: clock() + 8 * 60 * 1000 });
    return token;
  }
  async function klutchCall(userId, row, query, variables = {}, retryAuth = true) {
    const token = await sessionFor(userId, row);
    try {
      return await graphql(row.environment, query, variables, token);
    } catch (error) {
      if (!retryAuth) throw error;
      tokenCache.delete(userId);
      const fresh = await sessionFor(userId, row, true);
      return graphql(row.environment, query, variables, fresh);
    }
  }

  const ipLimits = new Map();
  function limit(bucket, max, period) {
    const time = clock();
    const old = ipLimits.get(bucket);
    const entry = old && old.until > time ? old : { count: 0, until: time + period };
    entry.count++;
    ipLimits.set(bucket, entry);
    if (ipLimits.size > 5000) for (const [k, v] of ipLimits) {
      if (v.until <= time) ipLimits.delete(k);
    }
    if (entry.count > max) throw new HttpError(429, 'Too many requests. Try again later.');
  }
  const allowedOrigins = new Set((env.NYXI_ALLOWED_ORIGINS || '')
    .split(',').map(v => v.trim()).filter(Boolean));

  const server = http.createServer(async (req, res) => {
    let origin = '';
    try {
      const requestOrigin = req.headers.origin;
      if (requestOrigin) {
        if (!allowedOrigins.has(requestOrigin)) throw new HttpError(403, 'Origin not allowed.');
        origin = requestOrigin;
      }
      if (req.method === 'OPTIONS') {
        res.writeHead(204, {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization,Content-Type,Idempotency-Key',
          'Access-Control-Max-Age': '300',
          Vary: 'Origin',
        });
        res.end(); return;
      }
      const url = new URL(req.url || '/', 'http://localhost');
      const route = url.pathname;
      if (req.method === 'GET' && route === '/health') {
        return json(res, 200, { status: 'ok', service: 'nyxi-api' }, origin);
      }
      if (route === '/api/auth/register' && req.method === 'POST') {
        limit('register:' + req.socket.remoteAddress, 5, 15 * 60 * 1000);
        if (env.NYXI_ALLOW_SIGNUPS !== 'true') {
          throw new HttpError(403, 'Registration is not enabled on this server.');
        }
        const body = await readBody(req);
        const email = string(body.email, 300).trim().toLowerCase();
        const password = body.password;
        if (!emailValid(email) || typeof password !== 'string' ||
            password.length < 12 || password.length > 128) {
          throw new HttpError(400, 'Enter a valid email and a 12–128 character password.');
        }
        if (db.prepare('SELECT id FROM users WHERE email = ?').get(email)) {
          throw new HttpError(409, 'This email is already registered.');
        }
        const salt = randomBytes(16).toString('hex');
        const hashed = await passwordHash(password, salt);
        const user = { id: randomId(), email };
        try {
          db.prepare(`INSERT INTO users (id,email,password_salt,password_hash,created_at)
            VALUES (?,?,?,?,?)`).run(user.id, email, salt, hashed, clock());
        } catch {
          throw new HttpError(409, 'This email is already registered.');
        }
        return json(res, 201, createSession(user), origin);
      }
      if (route === '/api/auth/login' && req.method === 'POST') {
        limit('login:' + req.socket.remoteAddress, 12, 15 * 60 * 1000);
        const body = await readBody(req);
        const email = string(body.email, 300).trim().toLowerCase();
        const password = body.password;
        if (!emailValid(email) || typeof password !== 'string' ||
            password.length > 128) throw new HttpError(401, 'Invalid email or password.');
        const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
        // Compare with a dummy hash for unknown users to reduce account enumeration.
        const salt = user?.password_salt || '00000000000000000000000000000000';
        const hash = await passwordHash(password, salt);
        const expected = user?.password_hash || '00'.repeat(64);
        if (!user || !timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(expected, 'hex'))) {
          throw new HttpError(401, 'Invalid email or password.');
        }
        return json(res, 200, createSession(user), origin);
      }
      const user = getUser(req);
      if (route === '/api/auth/me' && req.method === 'GET') {
        return json(res, 200, { user: { id: user.id, email: user.email } }, origin);
      }
      if (route === '/api/auth/logout' && req.method === 'POST') {
        db.prepare('DELETE FROM sessions WHERE token_hash = ?')
          .run(sha(req.headers.authorization.slice(7)));
        return json(res, 200, { signedOut: true }, origin);
      }
      if (route === '/api/klutch/status' && req.method === 'GET') {
        const row = connection(user.id);
        return json(res, 200, {
          connected: Boolean(row),
          environment: row?.environment || null,
          connectedAt: row?.created_at || null,
        }, origin);
      }
      if (route === '/api/klutch/connect' && req.method === 'POST') {
        limit('connect:' + user.id, 8, 60 * 60 * 1000);
        const body = await readBody(req);
        const clientId = string(body.clientId, 256).trim();
        const secretKey = string(body.secretKey, 512);
        const environment = body.environment === 'sandbox' ? 'sandbox' : 'production';
        if (clientId.length < 5 || secretKey.length < 8) {
          throw new HttpError(400, 'Enter your Klutch Client ID and Secret Key.');
        }
        const session = await graphql(environment, SESSION_QUERY, { clientId, secretKey });
        if (!session.createSessionToken || typeof session.createSessionToken !== 'string') {
          throw new ProviderError();
        }
        db.prepare(`INSERT INTO klutch_connections
          (user_id,client_enc,secret_enc,environment,created_at)
          VALUES (?,?,?,?,?)
          ON CONFLICT(user_id) DO UPDATE SET
          client_enc=excluded.client_enc,secret_enc=excluded.secret_enc,
          environment=excluded.environment,created_at=excluded.created_at`)
          .run(user.id, encrypt(clientId, user.id), encrypt(secretKey, user.id), environment, clock());
        tokenCache.set(user.id, { token: session.createSessionToken, expiresAt: clock() + 8 * 60 * 1000 });
        return json(res, 200, { connected: true, environment }, origin);
      }
      if (route === '/api/klutch/connect' && req.method === 'DELETE') {
        db.prepare('DELETE FROM klutch_connections WHERE user_id = ?').run(user.id);
        tokenCache.delete(user.id);
        return json(res, 200, { connected: false }, origin);
      }
      const row = connection(user.id);
      if (!row) throw new HttpError(409, 'Connect Klutch to your Nyxi account first.');
      if (route === '/api/klutch/cards' && req.method === 'GET') {
        const data = await klutchCall(user.id, row, CARDS_QUERY);
        return json(res, 200, {
          cards: Array.isArray(data.cards) ? data.cards.map(safeCard) : [],
        }, origin);
      }
      if (route === '/api/klutch/balance' && req.method === 'GET') {
        // Some Klutch products have no revolving loan. That must not be
        // reported as zero debt or as a checking-account cash balance.
        let outstandingBalance = null;
        let creditLimit = null;
        try {
          const data = await klutchCall(user.id, row, CREDIT_BALANCE_QUERY);
          const loan = object(object(data.account).revolvingLoan);
          const finite = value => {
            if (typeof value === 'number') return Number.isFinite(value) ? value : null;
            if (typeof value !== 'string') return null;
            const trimmed = value.trim();
            if (!/^-?\\d+(?:\\.\\d+)?$/.test(trimmed)) return null;
            const amount = Number(trimmed);
            return Number.isFinite(amount) ? amount : null;
          };
          outstandingBalance = finite(loan.balance);
          creditLimit = finite(loan.limit);
        } catch {
          // Leave unsupported credit-account values unavailable, not fake.
        }
        return json(res, 200, {
          source: 'klutch', currency: 'USD',
          accountType: 'revolving_credit',
          outstandingBalance, creditLimit,
          available: outstandingBalance !== null || creditLimit !== null,
        }, origin);
      }
      if (route === '/api/klutch/insights' && req.method === 'GET') {
        const now = new Date(clock());
        const first = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
        const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
        const period = first.toISOString().slice(0, 7);
        const filter = {
          startDate: first.toISOString(),
          endDate: new Date(next.getTime() - 1).toISOString(),
          transactionStatus: ['SETTLED'],
          transactionTypes: ['CHARGE'],
        };
        // An unavailable API query is NOT a zero-dollar spending month.
        let amount = null;
        try {
          const data = await klutchCall(user.id, row, MONTH_SPEND_QUERY, { filter });
          const value = data.sumTransactions;
          if ((typeof value === 'number' && Number.isFinite(value)) ||
              (typeof value === 'string' && /^-?\d+(?:\.\d+)?$/.test(value))) {
            const parsed = Number(value);
            if (Number.isFinite(parsed)) amount = parsed;
          }
        } catch {
          // The card and transaction panels remain available if this metric
          // isn't supported by the user's Klutch product.
        }
        return json(res, 200, {
          period, currency: 'USD', settledCharges: amount,
          source: 'klutch', available: amount !== null,
        }, origin);
      }
      if (route === '/api/klutch/transactions' && req.method === 'GET') {
        const data = await klutchCall(user.id, row, TX_QUERY, {
          sortOrder: 'UPDATED_DATE_DESC', limit: 30,
        });
        const page = object(data.transactionsPaginated);
        return json(res, 200, {
          transactions: Array.isArray(page.list) ? page.list.map(safeTransaction) : [],
          hasMore: Boolean(page.nextCursor),
        }, origin);
      }
      if (route === '/api/klutch/cards' && req.method === 'POST') {
        if (env.NYXI_ENABLE_CARD_ISSUANCE !== 'true') {
          throw new HttpError(403, 'Live card issuance is disabled on this Nyxi server.');
        }
        limit('issue:' + user.id, 3, 60 * 60 * 1000);
        const body = await readBody(req);
        const name = string(body.name, 128).trim();
        const requestKey = req.headers['idempotency-key'];
        if (body.confirm !== true || name.length < 2 || name.length > 60 ||
            typeof requestKey !== 'string' || !/^[0-9a-f-]{16,80}$/i.test(requestKey)) {
          throw new HttpError(400, 'Confirm a card name and provide a unique Idempotency-Key.');
        }
        const old = db.prepare(`SELECT state,response FROM card_requests
          WHERE user_id = ? AND request_key = ?`).get(user.id, requestKey);
        if (old) {
          if (old.state === 'complete') return json(res, 200, JSON.parse(old.response), origin);
          throw new HttpError(409, 'Card request is pending or uncertain. Check Klutch before retrying.');
        }
        db.prepare(`INSERT INTO card_requests
          (user_id,request_key,created_at,state) VALUES (?,?,?,?)`)
          .run(user.id, requestKey, clock(), 'pending');
        // Intentionally never automatically retry a financial mutation.
        const result = await klutchCall(user.id, row, CREATE_CARD,
          { name, media: 'VIRTUAL' }, false);
        if (!result.createCard) throw new ProviderError();
        const response = { card: safeCard(result.createCard) };
        db.prepare(`UPDATE card_requests SET state = 'complete',response = ?
          WHERE user_id = ? AND request_key = ?`)
          .run(JSON.stringify(response), user.id, requestKey);
        return json(res, 201, response, origin);
      }
      throw new HttpError(404, 'Route not found.');
    } catch (error) {
      return json(res, error instanceof HttpError ? error.status : 500, {
        error: error instanceof HttpError ? error.message : 'Server error.',
      }, origin);
    }
  });

  return { server, db, close() { tokenCache.clear(); db.close(); } };
}

if (process.argv[1] && import.meta.url === new URL('file://' + resolve(process.argv[1])).href) {
  const app = createNyxiServer();
  const port = Number(process.env.PORT || 8787);
  const host = process.env.HOST || '127.0.0.1';
  app.server.listen(port, host, () => {
    console.info(`Nyxi API listening on ${host}:${port}; use HTTPS reverse proxy for remote clients.`);
  });
}
