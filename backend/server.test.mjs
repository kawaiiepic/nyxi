import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHmac, randomBytes } from 'node:crypto';
import { after, before, test } from 'node:test';
import { createNyxiServer } from './server.mjs';

const temp = mkdtempSync(join(tmpdir(), 'nyxi-fluz-test-'));
const key = randomBytes(32).toString('hex');
const env = {
  NYXI_ENCRYPTION_KEY: key,
  NYXI_ALLOW_SIGNUPS: 'true',
  FLUZ_CLIENT_ID: 'test-app-client-id',
  FLUZ_CLIENT_SECRET: 'not-a-real-secret',
  FLUZ_REDIRECT_URI: 'http://localhost:8787/api/fluz/callback',
  FLUZ_API_KEY: 'test-webhook-signature-secret',
  FLUZ_ENV: 'staging',
};
const offerId = 'ed669305-5e43-40a0-9a25-7a15ed174628';
const cardId = '550e8400-e29b-41d4-a716-446655440123';
const calls = [];
const provider = async (endpoint, options) => {
  const url = new URL(endpoint);
  if (url.pathname === '/token/exchange') {
    const user = url.searchParams.get('code') === 'second-code' ? 'fluz-second' : 'fluz-first';
    assert.equal(options.headers.Authorization,
      'Basic ' + Buffer.from(env.FLUZ_CLIENT_ID + ':' + env.FLUZ_CLIENT_SECRET).toString('base64'));
    return Response.json({
      accessToken: 'access-' + user,
      refreshToken: 'refresh-' + user,
      accessTokenExpiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      user: { id: user },
    });
  }
  if (url.pathname === '/token/refresh') {
    return Response.json({
      accessToken: 'refreshed-' + url.searchParams.get('refresh_token'),
      refreshToken: 'rotated-token',
      accessTokenExpiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    });
  }
  assert.equal(url.pathname, '/api/v1/graphql');
  const { query, variables } = JSON.parse(options.body);
  calls.push({ query, variables, bearer: options.headers.Authorization });
  let data;
  if (query.includes('getWallet')) {
    data = { getWallet: { balances: {
      cashBalance: { availableBalance: '72.25' },
      rewardsBalance: { availableBalance: '5.00' },
      giftCardCashBalance: { availableBalance: '0.00' },
    } } };
  } else if (query.includes('getTransactions')) {
    data = { getTransactions: {
      transactions: [{
        recordId: 'transaction-id', transactionType: 'Virtual Card Purchase',
        amount: -12.50, status: 'SETTLED',
        createdAt: new Date().toISOString(), destination: 'Coffee',
      }],
      hasNextPage: false, totalCount: 1,
    } };
    if (variables.filter?.status) {
      assert.deepEqual(variables.filter.status, ['SETTLED']);
      assert.deepEqual(variables.filter.transactionType, ['Virtual Card Purchase']);
    }
  } else if (query.includes('getVirtualCardOffers')) {
    data = { getVirtualCardOffers: [{
      offerId, programName: 'Virtual Card', bankName: 'Issuer',
      rewardValue: '1.5%', programLimits: { monthlyLimit: '5000' },
    }] };
  } else if (query.includes('getCardProvisioningUrl')) {
    assert.equal(variables.virtualCardId, cardId);
    data = { getCardProvisioningUrl: {
      url: 'https://fluz.app.link/test-link',
      expiresAt: new Date(Date.now() + 300000).toISOString(),
    } };
  } else throw Error('Unexpected Fluz API call');
  return Response.json({ data });
};

const app = createNyxiServer({
  env, dbPath: join(temp, 'nyxi.sqlite'), fetchImpl: provider,
});
let base;

before(async () => {
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  base = 'http://127.0.0.1:' + app.server.address().port;
});
after(async () => {
  await new Promise(resolve => app.server.close(resolve));
  app.close();
  rmSync(temp, { recursive: true, force: true });
});

async function call(route, method = 'GET', token, payload, headers = {}) {
  const response = await fetch(base + route, {
    method, headers: {
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
      ...(payload ? { 'Content-Type': 'application/json' } : {}),
      ...headers,
    },
    ...(payload ? { body: JSON.stringify(payload) } : {}),
  });
  const raw = await response.text();
  let body;
  try { body = JSON.parse(raw); } catch { body = raw; }
  return { status: response.status, body };
}

test('Nyxi user login, Fluz consent and encrypted connection remain isolated', async () => {
  const health = await call('/health');
  assert.equal(health.body.service, 'nyxi-api');
  assert.equal((await call('/api/fluz/status')).status, 401);
  const first = await call('/api/auth/register', 'POST', null, {
    email: 'first@example.com', password: 'first-long-secure-password',
  });
  const second = await call('/api/auth/register', 'POST', null, {
    email: 'second@example.com', password: 'second-long-secure-password',
  });
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  assert.notEqual(first.body.token, second.body.token);
  for (const [session, code] of [[first, 'first-code'], [second, 'second-code']]) {
    const auth = await call('/api/fluz/authorize', 'GET', session.body.token);
    assert.equal(auth.status, 200);
    const url = new URL(auth.body.url);
    assert.equal(url.origin, 'https://uni.staging.fluzapp.com');
    assert.equal(url.searchParams.get('external_id'), session.body.user.id);
    assert.equal(url.searchParams.get('client_id'), env.FLUZ_CLIENT_ID);
    const state = url.searchParams.get('state');
    const callback = await call('/api/fluz/callback?state=' + state + '&code=' + code);
    assert.equal(callback.status, 200);
    assert.match(callback.body, /Fluz connected to Nyxi/);
    assert.equal((await call('/api/fluz/callback?state=' + state + '&code=' + code)).status, 400);
  }
  const rows = app.db.prepare('SELECT * FROM fluz_connections ORDER BY fluz_user_id').all();
  assert.equal(rows.length, 2);
  assert.equal(rows[0].access_enc.includes('access-fluz-first'), false);
  assert.equal(rows[1].refresh_enc.includes('refresh-fluz-second'), false);
  assert.equal((await call('/api/fluz/status', 'GET', first.body.token)).body.connected, true);
  assert.equal((await call('/api/fluz/cards', 'GET', second.body.token)).body.cards.length, 0);
  const tx = await call('/api/fluz/transactions', 'GET', first.body.token);
  assert.equal(tx.body.transactions[0].merchantName, 'Coffee');
  assert.equal(tx.body.transactions[0].amount, -12.5);
  const balance = await call('/api/fluz/balance', 'GET', first.body.token);
  assert.equal(balance.body.walletAvailable, 77.25);
  assert.equal(balance.body.accountType, 'wallet');
  assert.equal(balance.body.outstandingBalance, null);
  const insights = await call('/api/fluz/insights', 'GET', first.body.token);
  assert.equal(insights.body.settledCharges, 12.5);
  assert.match(insights.body.period, /^\\d{4}-\\d{2}$/);
  const offers = await call('/api/fluz/offers', 'GET', first.body.token);
  assert.equal(offers.body.offers[0].offerId, offerId);
  assert.equal((await call('/api/fluz/cards', 'POST', first.body.token, {
    name: 'Default', confirm: true, spendLimit: 100,
    offerId, period: 'MONTHLY', fundingSource: 'FLUZ_BALANCE',
  })).status, 403);
  assert.equal(calls.some(c => c.query.includes('createVirtualCard')), false);
  assert.notEqual(calls.find(c => c.query.includes('getWallet')).bearer, 'Bearer access-fluz-second');
  globalThis._nyxiFirst = first.body.token;
  globalThis._nyxiSecond = second.body.token;
});

test('Fluz webhook rejects unsigned events, deduplicates and isolates by Fluz account', async () => {
  const event = {
    eventType: 'TRANSACTION_CREATE', transactionId: 'tx-first',
    userId: 'fluz-first', accountId: 'first-account', transactionType: 'PURCHASE',
    amount: -29.99, status: 'PENDING', merchantName: 'Steam',
    createdAt: '2026-11-20T18:00:00Z',
  };
  const raw = JSON.stringify(event);
  const eventId = '123e4567-e89b-42d3-a456-426614174000';
  const bad = await fetch(base + '/api/fluz/webhook', { method: 'POST',
    body: raw, headers: {'X-HMAC-Signature': '0'.repeat(64), 'X-Event-ID': eventId} });
  assert.equal(bad.status, 401);
  const signature = createHmac('sha256', env.FLUZ_API_KEY).update(raw).digest('hex');
  const headers = {'X-HMAC-Signature': signature, 'X-Event-ID': eventId};
  const good = await fetch(base + '/api/fluz/webhook', { method: 'POST', body: raw, headers });
  assert.equal(good.status, 200);
  const repeat = await fetch(base + '/api/fluz/webhook', { method: 'POST', body: raw, headers });
  assert.equal(repeat.status, 200);
  assert.equal(app.db.prepare('SELECT count(*) AS n FROM fluz_events').get().n, 1);
  const first = await call('/api/fluz/events', 'GET', globalThis._nyxiFirst);
  const second = await call('/api/fluz/events', 'GET', globalThis._nyxiSecond);
  assert.equal(first.body.events[0].merchantName, 'Steam');
  assert.equal(first.body.events[0].transactionStatus, 'PENDING');
  assert.deepEqual(second.body.events, []);
});

test('Disconnect Fluz does not revoke Nyxi login', async () => {
  const disconnected = await call('/api/fluz/connect', 'DELETE', globalThis._nyxiFirst);
  assert.equal(disconnected.status, 200);
  assert.equal((await call('/api/fluz/status', 'GET', globalThis._nyxiFirst)).body.connected, false);
  assert.equal((await call('/api/fluz/cards', 'GET', globalThis._nyxiFirst)).status, 409);
  const whoami = await call('/api/auth/me', 'GET', globalThis._nyxiFirst);
  assert.equal(whoami.body.user.email, 'first@example.com');
  await call('/api/auth/logout', 'POST', globalThis._nyxiFirst);
  assert.equal((await call('/api/auth/me', 'GET', globalThis._nyxiFirst)).status, 401);
  assert.equal((await call('/api/fluz/status', 'GET', globalThis._nyxiSecond)).body.connected, true);
});
