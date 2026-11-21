# Nyxi ✦

Nyxi is a cybercute personal finance app using **Flutter, Cupertino, and `liquid_glass_widgets`** with a self-hosted Node.js/SQLite backend. The financial provider is **Fluz**. Nyxi shows real financial data from a user's authorized Fluz account and does not generate demo balances, cards, transactions, or transfers.

## Current capabilities

- Mandatory Nyxi registration/sign-in and a **live backend health check**. Nyxi locks its dashboard if its own server goes offline or a session expires. Checks run at startup, every 12 seconds, and on resume.
- Separate **Fluz OAuth account connection** after Nyxi login. Fluz credentials are entered on Fluz's own consent page, never pasted into Nyxi.
- Per-user, encrypted Fluz OAuth access/refresh tokens stored in SQLite using AES-256-GCM and an operator-controlled master key.
- Fluz **wallet available balance** (cash, rewards, prepayment components returned by `getWallet`). **Not a Chase bank checking or savings balance.**
- Fluz ledger transaction history and month-to-date **settled virtual card purchases** (not pending authorizations), using paginated `getTransactions` rather than only the first page.
- Real-time Fluz transaction webhook receiver for `TRANSACTION_CREATE`, `TRANSACTION_UPDATE`, and `TRANSACTION_DECLINE`. HMAC-SHA256 signature verification over the **raw request body**, persistent event-ID deduplication, account-specific event storage, and a 10-second app-side feed refresh.
- Browse Fluz virtual-card offers and, when explicitly enabled by the server operator, create a real card with a **chosen spending limit**, a displayed funding warning and unique idempotency key.
- Request short-lived **Apple Wallet / Google Pay provisioning links** for a specific card created through Nyxi, if the chosen Fluz card program supports tokenization.
- Desktop/mobile adaptive design with Liquid Glass. No Material app shell.

**Scope limitations:** The Cards section currently lists **cards issued through Nyxi**, not cards created elsewhere in Fluz. The app does not yet support editing spending limits or initiating a new Chase/Plaid bank link from Nyxi. Card issuance can select **Fluz wallet** or an **already-linked bank account** returned by Fluz's `getWallet.bankAccounts` query; bank-account funding requires its `bankAccountId`, and card-specific ACH holds/reservation rules must be confirmed. Card balances are **Fluz wallet funds**, not Chase deposits. Signed webhooks appear in the in-app activity feed; true background push notifications on iOS/Android/desktop would require a separate push-delivery integration.

## Requirements

- Flutter 3.41+ with a Dart SDK matching `pubspec.yaml`
- Node.js 22+ (`node:sqlite`, built-in, no external DB dependency)
- An **approved, ACTIVE Fluz OAuth Integration application** for a multi-user Nyxi deployment. An ordinary private Fluz developer app can act only on its owner's account and is not a substitute for user OAuth.
- The Fluz app must be configured with exactly the OAuth permissions it needs. Read transactions and purchase webhooks require **`LIST_PAYMENT` and `LIST_PURCHASES`**. Virtual-card offers/issuance and wallet provisioning require **`CREATE_VIRTUALCARD`**. Wallet access may have separate permissions depending on the Fluz application.
- A publicly reachable HTTPS hostname and registered OAuth redirect URL for remote and production use.

See [Fluz OAuth consent](https://docs.fluz.app/client-facing-o-auth-grant-flow.md), [webhooks](https://docs.fluz.app/fluz-dashboard/webhooks), [virtual card creation](https://docs.fluz.app/features/create-virtual-card), and [wallet provisioning](https://docs.fluz.app/digital-wallet-push-provisioning).

## Run the Nyxi backend

```bash
export NYXI_ENCRYPTION_KEY="$(openssl rand -hex 32)"
export NYXI_ALLOW_SIGNUPS=true
export NYXI_DB_PATH=./.data/nyxi.sqlite

# Fluz OAuth Integration app
export FLUZ_ENV=staging
export FLUZ_CLIENT_ID="your-fluz-oauth-client-id"
export FLUZ_CLIENT_SECRET="your-fluz-oauth-app-secret"
export FLUZ_REDIRECT_URI="https://api.your-nyxi-domain.example/api/fluz/callback"
export FLUZ_API_KEY="your-fluz-application-api-key-for-webhook-signatures"

# Staging uses Fluz's documented OAuth and API hosts by default.
# Production requires Fluz-issued OAuth hosts from onboarding:
# export FLUZ_ENV=production
# export FLUZ_AUTHORIZE_URL="https://approved-fluz-authorize-host/authorize"
# export FLUZ_TOKEN_URL="https://approved-fluz-token-host"

node backend/server.mjs
```

Use a permanent, backed-up, securely stored **`NYXI_ENCRYPTION_KEY`**; losing it makes encrypted Fluz connections unrecoverable. Never publish credentials, SQLite files, tokens, or webhook API keys. The server defaults to `127.0.0.1:8787`. Deploy behind HTTPS and restrict allowed cross-origin clients with `NYXI_ALLOWED_ORIGINS`. Set `HOST`/`PORT` only behind a configured proxy. Run rate limiting, log redaction, backups, account recovery, and a security review before opening signups publicly.

**Fluz OAuth callback**: `GET https://api.your-nyxi-domain.example/api/fluz/callback`

**Fluz signed webhook**: `POST https://api.your-nyxi-domain.example/api/fluz/webhook`

In Fluz's developer portal, register the exact OAuth callback URI, choose the required scopes, configure the webhook URL, and select at least `TRANSACTION_CREATE`, `TRANSACTION_UPDATE`, and `TRANSACTION_DECLINE`. The webhook key is stored on the backend only. Transaction webhooks may **not contain `externalReferenceId` in production**; Nyxi matches the Fluz user ID from the OAuth connection instead. Webhooks are not Chase debit-card purchase notifications.

For secure development, set a *local loopback* redirect and run a local staging flow; public webhook delivery still needs a valid HTTPS URL. Fluz onboarding is required for production OAuth hostnames.

### Fluz backend routes

| Route | Purpose |
| --- | --- |
| `GET /health` | Verify the Nyxi API |
| `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me` | Nyxi accounts and sessions |
| `GET /api/fluz/status` | User's Fluz connection |
| `GET /api/fluz/authorize` | One-use OAuth authorization URL |
| `GET /api/fluz/callback` | Public code-and-state callback |
| `DELETE /api/fluz/connect` | Disconnect user's Fluz account |
| `GET /api/fluz/balance` | Fluz wallet funds |
| `GET /api/fluz/transactions` | Recent Fluz ledger transactions |
| `GET /api/fluz/insights` | Month-to-date settled card purchases |
| `GET /api/fluz/events` | Signed webhook activity feed |
| `POST /api/fluz/webhook` | Public signed webhook receiver |
| `GET /api/fluz/cards` | Cards issued through Nyxi |
| `GET /api/fluz/offers` | Card programs eligible for the user |
| `GET /api/fluz/bank-accounts` | Masked Fluz-linked ACH funding accounts |
| `POST /api/fluz/cards` | Explicitly confirmed card issuance; **off by default** |
| `POST /api/fluz/wallet-provision` | Single-card Apple/Google Wallet link |

Issuance is **disabled by default**. The server operator must explicitly set `NYXI_ENABLE_CARD_ISSUANCE=true`, and the user must confirm the card name, offer, funding source and spending limit. For bank-funded cards, use an account previously linked through Fluz's app or Plaid flow; an ACH-backed payment may place a temporary hold on a backup card. A card operation can reserve or charge real money. Nyxi does not automatically retry an uncertain issuance response. Do not enable issuance until the exact Fluz card program and its funding behavior have been tested.

## Flutter

```bash
flutter create --platforms=android,ios,linux,windows .
flutter pub get
flutter run -d linux --dart-define=NYXI_API_URL=https://api.your-nyxi-domain.example
```

The platform runner directories are intentionally generated locally. The backend URL must be a reachable **HTTPS** origin in actual deployments; Nyxi allows loopback HTTP only for development (`127.0.0.1`, `localhost`, Android emulator `10.0.2.2`). The app stores the Nyxi session in memory only and requires re-login after restarting.

To connect, sign in to Nyxi, open **Cards → Connect Fluz**, approve Fluz's OAuth consent in the browser, return to Nyxi, and press **Refresh**. Until the OAuth Integration application is approved and configured, the app will not connect real Fluz accounts.

## Test

```bash
node --test backend/server.test.mjs
flutter analyze
flutter test
```

The Node tests use mock Fluz responses and simulate OAuth, encrypted per-user connections, token isolation, account-backed balances, blocked issuance, signed transaction events and deduplication. They do **not** create real cards or spend money. Flutter widget tests use a fake Nyxi backend. GitHub Actions runs both suites on pushes.

## Security and production readiness

This repository is a **developer integration preview**, not a production-ready fintech app. Fluz provider endpoints, scopes, OAuth grant approval, individual card programs and wallet provisioning have **not been validated with live Fluz credentials**. Never assume the signup/auth system, sensitive token storage, webhook handling, account provisioning, card funding, anti-abuse controls and compliance requirements are complete until production review and testing.

No fictional checking balance, credit debt, savings amount or card transaction is shown when provider data is unavailable.
