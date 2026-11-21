import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { after, before, test } from 'node:test';
import { createNyxiServer } from './server.mjs';

const directory = mkdtempSync(join(tmpdir(), 'nyxi-test-'));
const calls = [];
const provider = async (_url, options) => {
  const { query, variables } = JSON.parse(options.body);
  calls.push({ query, variables });
  let data;
  if (query.includes('createSessionToken')) {
    data = { createSessionToken: 'session-' + variables.clientId };
  } else if (query.includes('sumTransactions')) {
    assert.deepEqual(variables.filter.transactionStatus, ['SETTLED']);
    assert.deepEqual(variables.filter.transactionTypes, ['CHARGE']);
    assert.equal(typeof variables.filter.startDate, 'string');
    data = { sumTransactions: 41.75 };
  } else if (query.includes('transactionsPaginated')) {
    data = { transactionsPaginated: { nextCursor: null, list: [
      { id: 'tx1', merchantName: 'Cafe', transactionDate: '2026-11-20',
        amount: 12.5, transactionType: 'CHARGE', transactionStatus: 'SETTLED',
        card: { id: 'card1' }, unneededSecret: 'hidden' },
    ] } };
  } else if (query.includes('cards {')) {
    data = { cards: [
      { id: 'card1', name: options.headers.Authorization,
        lastFour: '9876', status: 'ACTIVE', media: 'VIRTUAL',
        pan: 'do-not-leak' },
    ] };
  } else throw new Error('Unexpected operation');
  return new Response(JSON.stringify({ data }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
};

const app = createNyxiServer({
  env: {
    NYXI_ENCRYPTION_KEY: randomBytes(32).toString('hex'),
    NYXI_ALLOW_SIGNUPS: 'true',
  },
  dbPath: join(directory, 'nyxi.sqlite'),
  fetchImpl: provider,
});
let endpoint;

before(async () => {
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  endpoint = 'http://127.0.0.1:' + app.server.address().port;
});
after(async () => {
  await new Promise(resolve => app.server.close(resolve));
  app.close();
  rmSync(directory, { force: true, recursive: true });
});

async function call(path, method = 'GET', token, payload) {
  const response = await fetch(endpoint + path, {
    method,
    headers: {
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
      ...(payload ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(payload ? { body: JSON.stringify(payload) } : {}),
  });
  return { status: response.status, body: await response.json() };
}

test('Nyxi logins isolate and encrypt each user Klutch connection', async () => {
  const anon = await call('/api/klutch/status');
  assert.equal(anon.status, 401);

  const first = await call('/api/auth/register', 'POST', null, {
    email: 'first@example.com', password: 'a-secure-password-of-12',
  });
  const second = await call('/api/auth/register', 'POST', null, {
    email: 'second@example.com', password: 'another-long-password',
  });
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  assert.notEqual(first.body.token, second.body.token);

  const connectFirst = await call('/api/klutch/connect', 'POST', first.body.token, {
    clientId: 'user-one-client',
    secretKey: 'user-one-private-key',
    environment: 'sandbox',
  });
  const connectSecond = await call('/api/klutch/connect', 'POST', second.body.token, {
    clientId: 'user-two-client',
    secretKey: 'user-two-private-key',
    environment: 'sandbox',
  });
  assert.equal(connectFirst.status, 200);
  assert.equal(connectSecond.status, 200);

  const rows = app.db.prepare(
    'SELECT user_id, client_enc, secret_enc FROM klutch_connections'
  ).all();
  assert.equal(rows.length, 2);
  for (const row of rows) {
    assert.equal(row.client_enc.includes('user-one-client'), false);
    assert.equal(row.secret_enc.includes('user-one-private-key'), false);
    assert.equal(row.secret_enc.includes('user-two-private-key'), false);
  }
  const firstCards = await call('/api/klutch/cards', 'GET', first.body.token);
  const secondCards = await call('/api/klutch/cards', 'GET', second.body.token);
  assert.equal(firstCards.status, 200);
  assert.equal(secondCards.status, 200);
  assert.equal(firstCards.body.cards[0].name, 'Bearer session-user-one-client');
  assert.equal(secondCards.body.cards[0].name, 'Bearer session-user-two-client');
  assert.equal(firstCards.body.cards[0].pan, undefined);

  const tx = await call('/api/klutch/transactions', 'GET', first.body.token);
  assert.equal(tx.status, 200);
  assert.equal(tx.body.transactions[0].merchantName, 'Cafe');
  assert.equal(tx.body.transactions[0].unneededSecret, undefined);

  const anonymousInsights = await call('/api/klutch/insights');
  assert.equal(anonymousInsights.status, 401);
  const spending = await call('/api/klutch/insights', 'GET', first.body.token);
  assert.equal(spending.status, 200);
  assert.equal(spending.body.settledCharges, 41.75);
  assert.equal(spending.body.currency, 'USD');
  assert.equal(spending.body.available, true);
  assert.match(spending.body.period, /^\d{4}-\d{2}$/);

  const issuance = await call('/api/klutch/cards', 'POST', first.body.token, {
    name: 'Subscriptions', confirm: true,
  });
  assert.equal(issuance.status, 403);

  const signOut = await call('/api/auth/logout', 'POST', first.body.token);
  assert.equal(signOut.status, 200);
  const invalidated = await call('/api/klutch/status', 'GET', first.body.token);
  assert.equal(invalidated.status, 401);
  const secondStatus = await call('/api/klutch/status', 'GET', second.body.token);
  assert.equal(secondStatus.body.connected, true);
});
