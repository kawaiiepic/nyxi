# Nyxi

A cybercute personal-finance app built with Flutter.

Nyxi is an authenticated desktop-and-mobile personal-finance dashboard. It retrieves actual credit balances, limits, virtual cards, transactions and month-to-date settled card charges through the central Nyxi API. It never invents bank balances or savings funds.

## Run

```bash
flutter create --platforms=android,ios,linux,windows .
flutter pub get
flutter run
```

The Flutter platform runner directories are intentionally generated locally. The tracked source, test, assets, and configuration live in this repository.

## Adaptive layouts

- **Mobile (< 600 logical pixels on desktop, < 900 on mobile/tablet):**
  preserves the original bright-pink, reference-inspired phone layout.
- **Desktop (600+ logical pixels on Linux/macOS/Windows):**
  switches to an edge-to-edge finance dashboard with a navigation sidebar,
  overview and balance panels, virtual-card management, recent activity,
  and savings.
- **Large tablets (900+ logical pixels):** use the dashboard layout.
- The desktop view deliberately uses a neutral canvas instead of the
  full-window pink/green preview backdrop. Liquid Glass stays enabled for
  navigation, buttons, and cards.
- All layouts share the same authenticated Nyxi API account and returned provider
  records. Account access is locked when Nyxi's backend is unreachable.

## Mandatory online sign-in

Nyxi has **no guest, offline or demo-only bypass**. On startup, every
desktop and mobile device checks the central backend's `GET /health`
response. It must identify the Nyxi service before the sign-in form appears.
A successful login is then confirmed with `GET /api/auth/me` before the
dashboard is mounted. Registering a new account follows the same checks.

The app checks backend availability and session validity every **12 seconds**,
and verifies again when resumed from the background. If the backend is
unreachable, times out, returns an invalid health response or rejects the
current session, the dashboard is immediately replaced by a lock/sign-in
screen. The UI **never** falls back to fabricated financial data on failure.
The lock screen offers Retry, and it periodically rechecks automatically.

The health request has a five-second HTTP timeout and the gate limits each
check to six seconds. The in-memory session may regain access after an outage
only if the backend responds and validates that same account again. Restarting
Nyxi always requires signing in because access tokens are not persisted.

To test these behaviors, run `flutter test test/nyxi_app_test.dart`.
The tests use a simulated Nyxi backend and do not require live Klutch keys.

## Live financial data only

Nyxi no longer contains mock balances, sample merchants, simulated deposits,
withdrawals or a fake virtual card. The mobile and desktop Home screens display
real data returned for the signed-in user:

- **Klutch credit balance and limit**: retrieved via the documented
  `account { revolvingLoan { balance limit } }` query through
  `GET /api/klutch/balance`. These are revolving-credit figures, **not**
  checking cash or savings balances. Some Klutch products may not expose
  these fields, in which case Nyxi shows **Not available**.
- **Monthly settled card charges**: computed by Klutch's
  `sumTransactions(filter: ...)` GraphQL query for settled `CHARGE`
  transactions within the current UTC month, served through
  `GET /api/klutch/insights`. If unavailable, Nyxi shows **Not available**
  instead of a made-up amount or zero.
- **Virtual cards**: fetched via `GET /api/klutch/cards`; only the masked
  last four digits, name and status are rendered. An unlinked account gets an
  empty state and an option to connect Klutch.
- **Recent activity**: fetched via `GET /api/klutch/transactions`; the
  list is explicitly limited to the first 30 records and is not a complete
  account statement.
- **Insights tab**: replaces the former fictional Savings tab. It displays
  the verified credit balance, limit, spending metric, number of cards
  and loaded transactions.
  A cash/bank account balance or savings balance is clearly marked
  unavailable until an actual banking data provider supports those values.

The former Add money, Withdraw, Move to savings, Move to cash and simulated card
freeze controls were removed. Nyxi cannot make cash transfers or represent
an unrelated Klutch credit-card balance as bank deposits. Real virtual-card
issuance uses the Klutch backend integration and remains disabled by default
until the server operator explicitly enables it.

## Nyxi accounts and Klutch integration

Nyxi now supports **central account registration, login, and per-user Klutch
connections**. Users do **not** run a Klutch gateway on their own computers.
They sign in to the same Nyxi backend and connect Klutch from **Cards**.

### Run the central API (server operator only)

Node.js 22+ is required because the API uses the built-in SQLite module.
From the repository directory, run:

```bash
export NYXI_ENCRYPTION_KEY="$(openssl rand -hex 32)"
export NYXI_ALLOW_SIGNUPS=true
export NYXI_DB_PATH=./.data/nyxi.sqlite
node backend/server.mjs
```

Keep `NYXI_ENCRYPTION_KEY` secure **and permanently backed up**. All Klutch
connections use authenticated AES-256-GCM encryption with per-user derived
keys. If this key is lost, encrypted connections cannot be recovered.
Never commit the key or database to Git. Use a password manager or secret
management service for production. User passwords use scrypt; Nyxi sessions
are opaque random tokens stored as hashes in SQLite.

By default, the API listens on **127.0.0.1:8787**. For actual multi-device
use, deploy **one backend** behind an HTTPS reverse proxy. Do not expose
plaintext HTTP to the public internet. Use `HOST` and `PORT` only in a
secured deployment, and configure `NYXI_ALLOWED_ORIGINS` when browser
clients require cross-origin access. For remote access, run Flutter with:

```bash
flutter run -d linux --dart-define=NYXI_API_URL=https://api.your-nyxi-domain.example
```

Android, iOS and Windows clients must also be configured with a reachable
HTTPS URL; localhost refers to the client's device, not your remote server.

### How a Nyxi user connects Klutch

1. Open **Cards → Create account** or **Sign in**.
2. Select **Paste Klutch key** and paste Klutch's API credential pair in
   **one input field**. Formats supported:
   - `clientId:secretKey`
   - A JSON object containing `clientId` and `secretKey`
   - Client ID and Secret Key on separate lines
3. Nyxi validates the credentials with Klutch and stores the encrypted
   connection in the user's backend account.
4. View masked cards, recent transactions, or issue a real virtual card
   when the server administrator has explicitly enabled issuance.

Klutch calls these API credentials an "API key", but its documented
`createSessionToken` mutation requires both the Client ID and Secret Key.
It does **not** support authenticating using an arbitrary lone secret key.
Documentation: https://api-docs.klutchcard.com/

### Important security and platform limits

- **This is a self-hosted developer preview, not ready for public users.**
  Central storage of users' Klutch developer secrets carries substantial
  risk. A production release should use Klutch's approved permissioned
  Mini App authorization instead of asking ordinary users to provide
  unrestricted developer credentials.
- Sign-ups are **disabled by default** unless `NYXI_ALLOW_SIGNUPS=true`.
  Add verified email, account recovery, persistent rate limits, auditing,
  abuse controls, backup/rotation procedures, and a deployment security
  review before opening Nyxi publicly.
- **Real card issuance is off by default.** To enable, set
  `NYXI_ENABLE_CARD_ISSUANCE=true` on the server, and require the user's
  explicit confirmation. Each request has a unique idempotency identifier
  and uncertain outcomes require manual review before retrying.
- User sessions are currently held **only in Flutter memory**. After
  restarting the app, users sign in again; the encrypted Klutch
  connection remains linked to their Nyxi account.
- Only the first 30 transactions are shown. Full card numbers, CVV, bank
  account transfers and live card locking are not requested or implemented.
- For API tests with a mock Klutch provider, run
  `node --test backend/server.test.mjs`. No real card is issued by tests.

## Liquid Glass UI

Nyxi uses [liquid_glass_widgets](https://pub.dev/packages/liquid_glass_widgets)
for real shader-based iOS-style navigation glass. The pastel background is
sampled by `GlassPage`, the floating navigation is `GlassTabBar.bottom`,
the card-freeze toggle is a `GlassSwitch`, and transaction/savings panels use
`GlassContainer.card(surfaceStyle: GlassSurfaceStyle.solid)` so account details
remain readable. The app uses `CupertinoApp` instead of Material.

Requires Flutter **3.41+**. The startup function preloads glass resources.
