import http from 'node:http';
import { createFluzService, FluzError } from './fluz.mjs';
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
const string = (value, limit = 128) => typeof value === 'string' ? value.slice(0, limit) : '';
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const sha = value => createHash('sha256').update(value).digest('hex');
const nowMs = () => Date.now();
const randomId = () => randomBytes(16).toString('hex');
const emailValid = value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
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
      Buffer.from(userId), Buffer.from('nyxi-fluz-v1'), 32));
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
      Buffer.from(userId), Buffer.from('nyxi-fluz-v1'), 32));
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
  const fluz = createFluzService({ db, env, fetchImpl, clock, encrypt, decrypt });

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
      // The Fluz redirect is public but guarded by a single-use, user-bound
      // OAuth state stored in SQLite. Do not require a Nyxi bearer token here.
      if (route === '/api/fluz/callback' && req.method === 'GET') {
        const code = url.searchParams.get('code') || '';
        const state = url.searchParams.get('state') || '';
        await fluz.callback(state, code);
        const html = '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><h2>Fluz connected to Nyxi</h2><p>Return to Nyxi and press Refresh.</p></body></html>';
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8',
          'Content-Length': Buffer.byteLength(html), 'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff' });
        res.end(html); return;
      }
      if (route === '/api/fluz/webhook' && req.method === 'POST') {
        let size = 0;
        const chunks = [];
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 128 * 1024) throw new HttpError(413, 'Webhook too large.');
          chunks.push(chunk);
        }
        fluz.webhook(Buffer.concat(chunks), req.headers['x-hmac-signature'],
          req.headers['x-event-id']);
        return json(res, 200, { received: true }, origin);
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
      if (route === '/api/fluz/status' && req.method === 'GET') {
        const row = fluz.connection(user.id);
        return json(res, 200, {
          connected: Boolean(row), environment: row?.environment || null,
          connectedAt: row?.created_at || null,
        }, origin);
      }
      if (route === '/api/fluz/authorize' && req.method === 'GET') {
        limit('oauth:' + user.id, 8, 60 * 60 * 1000);
        return json(res, 200, { url: fluz.begin(user.id) }, origin);
      }
      if (route === '/api/fluz/connect' && req.method === 'DELETE') {
        fluz.disconnect(user.id);
        return json(res, 200, { connected: false }, origin);
      }
      const row = fluz.connection(user.id);
      if (!row) throw new HttpError(409, 'Connect Fluz in Nyxi first.');
      if (route === '/api/fluz/cards' && req.method === 'GET') {
        return json(res, 200, { cards: fluz.cards(user.id),
          scope: 'cards_issued_via_nyxi' }, origin);
      }
      if (route === '/api/fluz/transactions' && req.method === 'GET') {
        return json(res, 200, await fluz.transactions(user.id), origin);
      }
      if (route === '/api/fluz/events' && req.method === 'GET') {
        return json(res, 200, { events: fluz.recentEvents(user.id) }, origin);
      }
      if (route === '/api/fluz/insights' && req.method === 'GET') {
        return json(res, 200, await fluz.monthly(user.id), origin);
      }
      if (route === '/api/fluz/balance' && req.method === 'GET') {
        return json(res, 200, await fluz.balance(user.id), origin);
      }
      if (route === '/api/fluz/offers' && req.method === 'GET') {
        return json(res, 200, { offers: await fluz.offers(user.id) }, origin);
      }
      if (route === '/api/fluz/wallet-provision' && req.method === 'POST') {
        const body = await readBody(req);
        return json(res, 200, await fluz.provisioning(
          user.id, string(body.offerId), string(body.platform)), origin);
      }
      if (route === '/api/fluz/cards' && req.method === 'POST') {
        if (env.NYXI_ENABLE_CARD_ISSUANCE !== 'true') {
          throw new HttpError(403, 'Card issuance is disabled on this Nyxi server.');
        }
        limit('issue:' + user.id, 3, 60 * 60 * 1000);
        const body = await readBody(req);
        const name = string(body.name, 60).trim();
        const key = req.headers['idempotency-key'];
        if (body.confirm !== true || name.length < 2 ||
            typeof key !== 'string') {
          throw new HttpError(400, 'Explicitly confirm a card name and unique request ID.');
        }
        const result = await fluz.issue(user.id, {
          name, requestKey: key, offerId: string(body.offerId),
          spendLimit: body.spendLimit, period: string(body.period),
          fundingSource: string(body.fundingSource),
          bankAccountId: string(body.bankAccountId),
        });
        return json(res, 201, result, origin);
      }
      throw new HttpError(404, 'Route not found.');
    } catch (error) {
      return json(res, error instanceof HttpError || error instanceof FluzError ? error.status : 500, {
        error: error instanceof HttpError || error instanceof FluzError ? error.message : 'Server error.',
      }, origin);
    }
  });

  return { server, db, close() { db.close(); } };
}

if (process.argv[1] && import.meta.url === new URL('file://' + resolve(process.argv[1])).href) {
  const app = createNyxiServer();
  const port = Number(process.env.PORT || 8787);
  const host = process.env.HOST || '127.0.0.1';
  app.server.listen(port, host, () => {
    console.info(`Nyxi API listening on ${host}:${port}; use HTTPS reverse proxy for remote clients.`);
  });
}
