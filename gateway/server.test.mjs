import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createApp } from './server.mjs';

const token = 'local-test-token-123456789000000';
const seen = [];

const fakeFetch = async (url, options) => {
  assert.equal(url, 'https://sandbox.klutchcard.com/graphql');
  const body = JSON.parse(options.body);
  seen.push({ query: body.query, variables: body.variables });
  let data;
  if (body.query.includes('createSessionToken')) {
    assert.equal(body.variables.clientId, 'fixture-client');
    assert.equal(body.variables.secretKey, 'fixture-secret');
    data = { createSessionToken: 'temporary-session' };
  } else {
    assert.equal(options.headers.Authorization, 'Bearer temporary-session');
    if (body.query.includes('transactionsPaginated')) {
      data = {
        transactionsPaginated: {
          nextCursor: null,
          list: [{
            id: 't1',
            merchantName: 'Coffee',
            transactionDate: '2026-11-20T12:00:00Z',
            amount: 7.50,
            transactionStatus: 'SETTLED',
            transactionType: 'CHARGE',
            card: { id: 'c1' },
          }],
        },
      };
    } else if (body.query.includes('createCard')) {
      assert.deepEqual(body.variables, { name: 'Subscriptions', media: 'VIRTUAL' });
      data = {
        createCard: {
          id: 'c2',
          name: 'Subscriptions',
          media: 'VIRTUAL',
          status: 'ACTIVE',
          lastFour: '4321',
        },
      };
    } else if (body.query.includes('cards')) {
      data = {
        cards: [{
          id: 'c1',
          name: 'Shopping',
          media: 'VIRTUAL',
          status: 'ACTIVE',
          lockState: 'UNLOCKED',
          lastFour: '1234',
          pan: 'DO-NOT-EXPOSE',
        }],
      };
    } else {
      throw new Error('Unexpected GraphQL operation');
    }
  }
  return new Response(JSON.stringify({ data }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};

const server = createApp({
  env: {
    KLUTCH_ENV: 'sandbox',
    KLUTCH_CLIENT_ID: 'fixture-client',
    KLUTCH_SECRET_KEY: 'fixture-secret',
    NYXI_GATEWAY_TOKEN: token,
  },
  fetchImpl: fakeFetch,
});
let base;
before(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = 'http://127.0.0.1:' + server.address().port;
});
after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

test('rejects unauthenticated card reads and issuance', async () => {
  const read = await fetch(base + '/api/klutch/cards');
  assert.equal(read.status, 401);
  const write = await fetch(base + '/api/klutch/cards', { method: 'POST' });
  assert.equal(write.status, 401);
});

test('lists masked real cards, never returns raw card secrets', async () => {
  const response = await fetch(base + '/api/klutch/cards', {
    headers: { Authorization: 'Bearer ' + token },
  });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.cards[0].lastFour, '1234');
  assert.equal(data.cards[0].pan, undefined);
});

test('loads recent real transactions from the paginated API', async () => {
  const response = await fetch(base + '/api/klutch/transactions', {
    headers: { Authorization: 'Bearer ' + token },
  });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.transactions[0].merchantName, 'Coffee');
  assert.equal(data.transactions[0].amount, 7.5);
  assert.equal(data.hasMore, false);
});

test('validates and confirms real virtual card issuance', async () => {
  const headers = {
    Authorization: 'Bearer ' + token,
    'Content-Type': 'application/json',
  };
  const invalid = await fetch(base + '/api/klutch/cards', {
    method: 'POST',
    headers,
    body: JSON.stringify({ name: 'A' }),
  });
  assert.equal(invalid.status, 400);
  const valid = await fetch(base + '/api/klutch/cards', {
    method: 'POST',
    headers,
    body: JSON.stringify({ name: 'Subscriptions' }),
  });
  assert.equal(valid.status, 201);
  const data = await valid.json();
  assert.equal(data.card.name, 'Subscriptions');
  assert.equal(data.card.media, 'VIRTUAL');
  assert.equal(seen.some(item => item.query.includes('createCard')), true);
});
