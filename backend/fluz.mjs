import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

const str = (v, limit = 180) => typeof v === 'string' ? v.slice(0, limit) : '';
const obj = v => v && typeof v === 'object' && !Array.isArray(v) ? v : {};
const number = v => {
  if (typeof v !== 'number' && (typeof v !== 'string' || !/^-?\d+(?:\.\d+)?$/.test(v))) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};
const hash = value => createHash('sha256').update(value).digest('hex');
const TRANSACTIONS = `query($filter:TransactionFilterInput,$paginate:OffsetInput) {
  getTransactions(filter:$filter,paginate:$paginate) {
    transactions { recordId transactionType amount status createdAt destination description cardLastFour }
    hasNextPage totalCount
  }
}`;
const WALLET = `query { getWallet { balances {
  cashBalance { availableBalance }
  rewardsBalance { availableBalance }
  giftCardCashBalance { availableBalance }
} } }`;
const OFFERS = `query { getVirtualCardOffers {
  offerId programName bankName rewardValue
  programLimits { dailyLimit weeklyLimit monthlyLimit }
} }`;
const CREATE = `mutation($input:CreateVirtualCardInput!) { createVirtualCard(input:$input) {
  virtualCardId virtualCardLast4 status cardType expiryMonth expiryYear initialAmount createdAt
} }`;
const PROVISION = `query($virtualCardId:String!,$platform:ProvisioningPlatform!) {
  getCardProvisioningUrl(input:{ virtualCardId:$virtualCardId, platform:$platform }) { url expiresAt }
}`;

export class FluzError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function createFluzService({ db, env, fetchImpl, clock, encrypt, decrypt }) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS fluz_connections (
      user_id TEXT PRIMARY KEY, access_enc TEXT NOT NULL, refresh_enc TEXT NOT NULL,
      access_expires_at INTEGER NOT NULL, fluz_user_id TEXT NOT NULL,
      fluz_account_id TEXT, environment TEXT NOT NULL, created_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS fluz_oauth_states (
      state_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS fluz_cards (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, name TEXT NOT NULL, last_four TEXT,
      status TEXT, card_type TEXT, offer_id TEXT NOT NULL, initial_amount REAL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS fluz_events (
      event_id TEXT PRIMARY KEY, received_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS fluz_activity (
      user_id TEXT NOT NULL, transaction_id TEXT NOT NULL,
      merchant_name TEXT, transaction_date TEXT, amount REAL,
      transaction_status TEXT, transaction_type TEXT, card_id TEXT,
      reference_id TEXT, last_updated INTEGER NOT NULL,
      PRIMARY KEY(user_id,transaction_id),
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  `);

  const staging = env.FLUZ_ENV !== 'production';
  const apiUrl = staging ? 'https://transactional-graph.staging.fluzapp.com/api/v1/graphql' :
    'https://api.fluz.app/api/v1/graphql';
  const authorizeUrl = env.FLUZ_AUTHORIZE_URL || (staging ? 'https://uni.staging.fluzapp.com/authorize' : '');
  const tokenUrl = env.FLUZ_TOKEN_URL || (staging ? 'https://uni.staging.fluzapp.com' : '');
  const clientId = str(env.FLUZ_CLIENT_ID, 512);
  const clientSecret = str(env.FLUZ_CLIENT_SECRET, 1024);
  const redirectUri = str(env.FLUZ_REDIRECT_URI, 1024);
  const webhookKey = str(env.FLUZ_API_KEY, 1024);
  const basic = 'Basic ' + Buffer.from(clientId + ':' + clientSecret).toString('base64');

  function configured() {
    if (!clientId || !clientSecret || !redirectUri || !authorizeUrl || !tokenUrl) {
      throw new FluzError(503, 'Fluz OAuth has not been configured on the Nyxi server.');
    }
    for (const value of [authorizeUrl, tokenUrl, redirectUri]) {
      try {
        const url = new URL(value);
        if (url.protocol !== 'https:' &&
            !(value === redirectUri && url.protocol === 'http:' &&
              ['127.0.0.1', 'localhost'].includes(url.hostname))) throw new Error();
      } catch { throw new FluzError(503, 'Fluz URLs must use HTTPS.'); }
    }
  }

  async function request(url, options) {
    let response;
    try {
      response = await fetchImpl(url, { ...options, signal: AbortSignal.timeout(12000) });
    } catch {
      throw new FluzError(502, 'Fluz is currently unreachable.');
    }
    let body;
    try { body = await response.json(); }
    catch { throw new FluzError(502, 'Fluz returned an unreadable response.'); }
    if (!response.ok) throw new FluzError(502, 'Fluz rejected this request. Reconnect if access expired.');
    return body;
  }

  async function graph(access, query, variables = {}) {
    const data = await request(apiUrl, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + access, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, variables }),
    });
    if (data.errors?.length || !data.data) {
      throw new FluzError(502, 'Fluz did not permit that operation or returned an error.');
    }
    return obj(data.data);
  }

  function connection(userId) {
    return db.prepare('SELECT * FROM fluz_connections WHERE user_id = ?').get(userId);
  }

  function begin(userId) {
    configured();
    const state = randomBytes(32).toString('hex');
    db.prepare('DELETE FROM fluz_oauth_states WHERE expires_at <= ?').run(clock());
    db.prepare('INSERT INTO fluz_oauth_states(state_hash,user_id,expires_at) VALUES(?,?,?)')
      .run(hash(state), userId, clock() + 10 * 60 * 1000);
    const url = new URL(authorizeUrl);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('client_id', clientId);
    url.searchParams.set('redirect_uri', redirectUri);
    url.searchParams.set('state', state);
    url.searchParams.set('external_id', userId);
    return url.toString();
  }

  async function callback(state, code) {
    configured();
    if (!/^[a-f0-9]{64}$/.test(state) || typeof code !== 'string' ||
        code.length < 2 || code.length > 4096) throw new FluzError(400, 'Invalid Fluz authorization response.');
    const pending = db.prepare('SELECT user_id,expires_at FROM fluz_oauth_states WHERE state_hash = ?').get(hash(state));
    if (!pending || pending.expires_at <= clock()) throw new FluzError(400, 'Fluz authorization expired. Start again in Nyxi.');
    db.prepare('DELETE FROM fluz_oauth_states WHERE state_hash = ?').run(hash(state));
    const url = new URL('/token/exchange', tokenUrl);
    url.searchParams.set('code', code);
    url.searchParams.set('redirect_uri', redirectUri);
    const payload = await request(url.toString(), { headers: { Authorization: basic } });
    if (!str(payload.accessToken) || !str(payload.refreshToken)) {
      throw new FluzError(502, 'Fluz authorization did not provide usable tokens.');
    }
    const fluzUserId = str(obj(payload.user).id, 128);
    if (!fluzUserId) throw new FluzError(502, 'Fluz authorization did not identify an account holder.');
    // A Fluz identity must not be mapped to two unrelated Nyxi logins.
    const existingOwner = db.prepare(
      'SELECT user_id FROM fluz_connections WHERE fluz_user_id = ? AND user_id <> ?'
    ).get(fluzUserId, pending.user_id);
    if (existingOwner) throw new FluzError(409, 'This Fluz account is already connected to another Nyxi account.');
    const previous = connection(pending.user_id);
    if (previous && previous.fluz_user_id !== fluzUserId) {
      db.prepare('DELETE FROM fluz_cards WHERE user_id = ?').run(pending.user_id);
      db.prepare('DELETE FROM fluz_activity WHERE user_id = ?').run(pending.user_id);
    }
    const expires = Date.parse(str(payload.accessTokenExpiresAt, 80));
    db.prepare(`INSERT INTO fluz_connections
      (user_id,access_enc,refresh_enc,access_expires_at,fluz_user_id,fluz_account_id,environment,created_at)
      VALUES (?,?,?,?,?,?,?,?)
      ON CONFLICT(user_id) DO UPDATE SET access_enc=excluded.access_enc,
      refresh_enc=excluded.refresh_enc,access_expires_at=excluded.access_expires_at,
      fluz_user_id=excluded.fluz_user_id,fluz_account_id=excluded.fluz_account_id,
      environment=excluded.environment,created_at=excluded.created_at`)
      .run(pending.user_id, encrypt(payload.accessToken, pending.user_id),
        encrypt(payload.refreshToken, pending.user_id),
        Number.isFinite(expires) ? expires : clock() + 5 * 60 * 1000,
        fluzUserId, str(obj(payload.account).id, 128) || null,
        staging ? 'staging' : 'production', clock());
    return pending.user_id;
  }

  const pendingRefreshes = new Map();
  async function tokenFor(userId, force = false) {
    const row = connection(userId);
    if (!row) throw new FluzError(409, 'Connect your Fluz account in Nyxi first.');
    if (!force && row.access_expires_at > clock() + 30_000)
      return decrypt(row.access_enc, userId);
    if (pendingRefreshes.has(userId)) return pendingRefreshes.get(userId);
    const work = (async () => {
      configured();
      const url = new URL('/token/refresh', tokenUrl);
      url.searchParams.set('refresh_token', decrypt(row.refresh_enc, userId));
      const payload = await request(url.toString(), { headers: { Authorization: basic } });
      if (!str(payload.accessToken)) throw new FluzError(502, 'Fluz token refresh failed. Reconnect your account.');
      const expires = Date.parse(str(payload.accessTokenExpiresAt, 80));
      db.prepare(`UPDATE fluz_connections SET access_enc=?,refresh_enc=?,access_expires_at=? WHERE user_id=?`)
        .run(encrypt(payload.accessToken, userId),
          encrypt(str(payload.refreshToken) || decrypt(row.refresh_enc, userId), userId),
          Number.isFinite(expires) ? expires : clock() + 5 * 60 * 1000, userId);
      return payload.accessToken;
    })();
    pendingRefreshes.set(userId, work);
    try { return await work; } finally { pendingRefreshes.delete(userId); }
  }

  async function call(userId, query, variables = {}) {
    return graph(await tokenFor(userId), query, variables);
  }

  function safeTransaction(t) {
    const value = obj(t);
    return {
      id: str(value.recordId || value.transactionId),
      merchantName: str(value.merchantName || value.destination || value.description, 128) || 'Fluz transaction',
      transactionDate: str(value.createdAt || value.transactionDateTime, 64),
      amount: number(value.amount) ?? 0,
      transactionStatus: str(value.status),
      transactionType: str(value.transactionType),
      cardId: str(value.virtualCardId),
    };
  }

  async function transactionPage(userId, filter, offset = 0) {
    const result = await call(userId, TRANSACTIONS, { filter, paginate: { limit: 20, offset } });
    return obj(result.getTransactions);
  }

  async function transactions(userId) {
    const pages = [];
    let hasMore = false;
    for (let offset = 0; offset < 40; offset += 20) {
      const page = await transactionPage(userId, {}, offset);
      const items = Array.isArray(page.transactions) ? page.transactions : [];
      pages.push(...items);
      hasMore = Boolean(page.hasNextPage);
      if (!hasMore) break;
    }
    return { transactions: pages.map(safeTransaction), hasMore };
  }

  async function monthly(userId) {
    const date = new Date(clock());
    const from = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
    const period = from.toISOString().slice(0, 7);
    let sum = 0;
    let finished = false;
    for (let offset = 0; offset < 2000; offset += 20) {
      const page = await transactionPage(userId, {
        createdGte: from.toISOString(), status: ['SETTLED'],
        transactionType: ['Virtual Card Purchase'],
      }, offset);
      const rows = Array.isArray(page.transactions) ? page.transactions : [];
      for (const row of rows) {
        const amount = number(row.amount);
        if (amount === null) throw new FluzError(502, 'Fluz returned a transaction without a valid amount.');
        sum += Math.abs(amount);
      }
      if (!page.hasNextPage) { finished = true; break; }
    }
    if (!finished) throw new FluzError(503, 'Monthly spending is too large to summarize safely.');
    return { period, currency: 'USD', settledCharges: Math.round(sum * 100) / 100,
      source: 'fluz', available: true };
  }

  async function balance(userId) {
    const data = await call(userId, WALLET);
    const balances = obj(obj(data.getWallet).balances);
    const parts = [balances.cashBalance, balances.rewardsBalance, balances.giftCardCashBalance];
    const nums = parts.map(p => number(obj(p).availableBalance));
    const any = nums.some(v => v !== null);
    return { source: 'fluz', accountType: 'wallet', currency: 'USD',
      walletAvailable: any ? nums.reduce((a, b) => a + (b ?? 0), 0) : null,
      outstandingBalance: null, creditLimit: null, available: any };
  }

  function cards(userId) {
    return db.prepare(`SELECT id,name,last_four,status,card_type,initial_amount,offer_id FROM fluz_cards
      WHERE user_id=? ORDER BY created_at DESC LIMIT 100`).all(userId).map(c => ({
        id: c.id, name: c.name, lastFour: c.last_four || '', status: c.status || '',
        media: 'VIRTUAL', lockState: '', expirationDate: '',
        cardType: c.card_type || '', spendLimit: c.initial_amount, offerId: c.offer_id,
      }));
  }

  async function offers(userId) {
    const data = await call(userId, OFFERS);
    return (Array.isArray(data.getVirtualCardOffers) ? data.getVirtualCardOffers : [])
      .map(o => ({ offerId: str(o.offerId), programName: str(o.programName),
        bankName: str(o.bankName), rewardValue: str(o.rewardValue),
        programLimits: obj(o.programLimits) })).filter(o => o.offerId);
  }

  async function issue(userId, { name, spendLimit, offerId, period, requestKey, fundingSource, bankAccountId }) {
    if (!/^[a-f0-9-]{36}$/i.test(requestKey) ||
        !/^[0-9a-f-]{36}$/i.test(offerId) ||
        !Number.isFinite(spendLimit) || spendLimit <= 0 || spendLimit > 100000 ||
        !['DAILY','WEEKLY','MONTHLY','LIFETIME'].includes(period) ||
        !['FLUZ_BALANCE','BANK_ACCOUNT'].includes(fundingSource) ||
        (fundingSource === 'BANK_ACCOUNT' && !/^[a-f0-9-]{36}$/i.test(bankAccountId || ''))) {
      throw new FluzError(400, 'Choose an eligible offer, valid spending limit, and funding source.');
    }
    const existing = db.prepare('SELECT state,response FROM card_requests WHERE user_id=? AND request_key=?')
      .get(userId, requestKey);
    if (existing) {
      if (existing.state === 'complete') return JSON.parse(existing.response);
      throw new FluzError(409, 'Card issuance outcome uncertain. Verify with Fluz before retrying.');
    }
    db.prepare('INSERT INTO card_requests(user_id,request_key,created_at,state) VALUES(?,?,?,?)')
      .run(userId, requestKey, clock(), 'pending');
    const input = { idempotencyKey: requestKey, spendLimit, offerId, spendLimitDuration: period,
      cardNickname: name, lockCardNextUse: false, primaryFundingSource: fundingSource };
    if (fundingSource === 'BANK_ACCOUNT') input.bankAccountId = bankAccountId;
    // No retry on financial mutations, even when the response is lost.
    const data = await call(userId, CREATE, { input });
    const c = obj(data.createVirtualCard);
    if (!str(c.virtualCardId)) throw new FluzError(502, 'Fluz did not confirm issuance.');
    db.prepare(`INSERT OR REPLACE INTO fluz_cards
      (id,user_id,name,last_four,status,card_type,offer_id,initial_amount,created_at)
      VALUES(?,?,?,?,?,?,?,?,?)`).run(c.virtualCardId, userId, name,
        str(c.virtualCardLast4, 4), str(c.status), str(c.cardType),
        offerId, number(c.initialAmount), clock());
    const card = cards(userId).find(x => x.id === c.virtualCardId);
    const response = { card };
    db.prepare('UPDATE card_requests SET state=?,response=? WHERE user_id=? AND request_key=?')
      .run('complete', JSON.stringify(response), userId, requestKey);
    return response;
  }

  async function provisioning(userId, cardId, platform) {
    if (!/^[0-9a-f-]{36}$/i.test(cardId) ||
        !['IOS','ANDROID'].includes(platform)) throw new FluzError(400, 'Invalid wallet request.');
    // Using a card ID avoids ambiguous offers when multiple cards share the program.
    const own = db.prepare('SELECT id,status FROM fluz_cards WHERE user_id=? AND id=?')
      .get(userId, cardId);
    if (!own) throw new FluzError(404, 'Card not found.');
    if (own.status !== 'ACTIVE') throw new FluzError(409, 'Card is not active for wallet provisioning.');
    const data = await call(userId, PROVISION, { virtualCardId: cardId, platform });
    const value = obj(data.getCardProvisioningUrl);
    const url = str(value.url, 2048);
    if (!url.startsWith('https://')) throw new FluzError(502, 'Fluz wallet provisioning is unavailable.');
    return { url, expiresAt: str(value.expiresAt) };
  }

  function disconnect(userId) {
    db.prepare('DELETE FROM fluz_connections WHERE user_id=?').run(userId);
    db.prepare('DELETE FROM fluz_cards WHERE user_id=?').run(userId);
    db.prepare('DELETE FROM fluz_activity WHERE user_id=?').run(userId);
  }

  function webhook(raw, signature, eventId) {
    if (!webhookKey) throw new FluzError(503, 'Fluz webhook signing key is not configured.');
    if (!/^[a-f0-9]{64}$/i.test(signature || '')) throw new FluzError(401, 'Invalid webhook signature.');
    const expected = createHmac('sha256', webhookKey).update(raw).digest();
    const given = Buffer.from(signature, 'hex');
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) {
      throw new FluzError(401, 'Invalid webhook signature.');
    }
    if (!/^[0-9a-f-]{20,80}$/i.test(eventId || '')) throw new FluzError(400, 'Missing webhook event ID.');
    let event;
    try { event = obj(JSON.parse(raw.toString('utf8'))); }
    catch { throw new FluzError(400, 'Invalid webhook JSON.'); }
    if (db.prepare('SELECT 1 FROM fluz_events WHERE event_id=?').get(eventId)) return { duplicate: true };
    const type = str(event.eventType);
    const row = db.prepare(`SELECT user_id FROM fluz_connections WHERE
      fluz_user_id=? AND (fluz_account_id=? OR fluz_account_id IS NULL)`)
      .get(str(event.userId), str(event.accountId));
    // Production transaction webhooks do NOT contain externalReferenceId yet.
    if (row?.user_id && type === 'OAUTH_USER_UNLINKED') disconnect(row.user_id);
    if (row?.user_id && ['TRANSACTION_CREATE','TRANSACTION_UPDATE','TRANSACTION_DECLINE'].includes(type)) {
      const txId = str(event.transactionId || event.recordId, 128);
      if (txId) {
        const old = db.prepare('SELECT last_updated FROM fluz_activity WHERE user_id=? AND transaction_id=?')
          .get(row.user_id, txId);
        const timestamp = Date.parse(str(event.updatedAt || event.createdAt || event.transactionDateTime, 64));
        const when = Number.isFinite(timestamp) ? timestamp : clock();
        if (!old || when >= old.last_updated) {
          db.prepare(`INSERT INTO fluz_activity
            (user_id,transaction_id,merchant_name,transaction_date,amount,transaction_status,
             transaction_type,card_id,reference_id,last_updated)
            VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(user_id,transaction_id) DO UPDATE SET
              merchant_name=excluded.merchant_name,transaction_date=excluded.transaction_date,
              amount=excluded.amount,transaction_status=excluded.transaction_status,
              transaction_type=excluded.transaction_type,card_id=excluded.card_id,
              reference_id=excluded.reference_id,last_updated=excluded.last_updated`)
            .run(row.user_id, txId, str(event.merchantName || event.destination) || 'Fluz transaction',
              str(event.createdAt || event.transactionDateTime),
              number(event.amount), str(event.status),
              str(event.transactionType), str(event.virtualCardId),
              str(event.referenceId), when);
        }
      }
    }
    db.prepare('INSERT INTO fluz_events(event_id,received_at) VALUES(?,?)').run(eventId, clock());
    return { duplicate: false };
  }

  function recentEvents(userId) {
    return db.prepare(`SELECT transaction_id,merchant_name,transaction_date,amount,
      transaction_status,transaction_type,card_id FROM fluz_activity
      WHERE user_id=? ORDER BY last_updated DESC LIMIT 30`).all(userId).map(e => ({
      id: e.transaction_id, merchantName: e.merchant_name, transactionDate: e.transaction_date,
      amount: e.amount, transactionStatus: e.transaction_status,
      transactionType: e.transaction_type, cardId: e.card_id,
    }));
  }

  return { begin, callback, connection, disconnect, cards, offers, issue,
    transactions, monthly, balance, provisioning, webhook, recentEvents };
}
