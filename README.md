# Nyxi ✦

A cybercute Flutter finance dashboard with Cupertino, `liquid_glass_widgets`, and a separate authenticated Fluz backend. No demo mode, fictional balances, transactions, cards, or guest sign-in.

## Repositories

- **Flutter app:** [kawaiiepic/nyxi](https://github.com/kawaiiepic/nyxi) (this repository)
- **Fluz API + Docker Compose deployment:** [kawaiiepic/nyxi-backend](https://github.com/kawaiiepic/nyxi-backend) (private)

All financial API credentials, Fluz OAuth secrets, transaction webhook verification and SQLite storage belong to **`nyxi-backend`**. The Flutter app never needs a Fluz API key.

The public [Nyxi landing page](https://nyxi.blossomvale.dev/) is served separately through Traefik when deployed with the backend repository's optional Traefik Compose overlay. On the same domain, `/api/*` and `/health` route to the authenticated Node API. The landing page itself doesn't contain financial data. The backend repository includes the `Dockerfile`, `docker-compose.yml`, `.env.example`, `.dockerignore`, tests and deployment guide.

## Run Flutter

```bash
flutter create --platforms=android,ios,linux,windows .
flutter pub get
flutter run -d linux
```

Flutter 3.41+ is required. Platform runner directories are generated locally. The API origin is hardcoded in `lib/fluz_gateway.dart` to **`https://nyxi.blossomvale.dev`** on all platforms; no `--dart-define` is needed. Your backend must be reachable via **HTTPS** from the device. For development only, Nyxi also allows `localhost`, `127.0.0.1`, and Android emulator `10.0.2.2` over plain HTTP. Android/iOS devices cannot use the Linux desktop's `127.0.0.1`; use your backend HTTPS hostname.

Use the separate backend repository to configure the `.env` secrets, Docker Compose service, HTTPS proxy, Fluz OAuth callback, and transaction webhooks.

## Account and Fluz connection

- Nyxi requires a valid authenticated central-backend session. No guest, offline, or demo-only access.
- On startup, and approximately every 12 seconds while the app is ready, it checks `GET /health` and `GET /api/auth/me`. An unresponsive or invalid backend locks the dashboard until authentication and health recover.
- Sessions are held in memory only. Restarting Nyxi requires signing in again.
- **OAuth mode:** In **Cards → Connect Fluz**, Nyxi opens Fluz's authorization page. The backend handles the callback, stores encrypted tokens, and connects the correct Nyxi account.
- **Single-account API-key mode:** Set `FLUZ_AUTH_MODE=api_key`, `FLUZ_API_KEY`, `FLUZ_USER_ID`, `FLUZ_ACCOUNT_ID`, and `NYXI_FLUZ_OWNER_USER_ID` in the [backend's private `.env`](https://github.com/kawaiiepic/nyxi-backend/blob/main/.env.example). The designated Nyxi login automatically shows Fluz as server-managed, without an OAuth popup. The key is **never entered in Flutter** and is not shared with other Nyxi accounts. See the [backend API-key setup guide](https://github.com/kawaiiepic/nyxi-backend#personal-fluz-api-key-mode-no-oauth-client-id-needed).
- An approved Fluz OAuth Integration application is still needed to connect *distinct users*. Live API-key mode may also be restricted if Fluz hasn't activated your developer application. The backend is not yet verified with live credentials or card programs.

## Live financial data

Nyxi can show authorized Fluz wallet balances, recent ledger transactions, month-to-date settled virtual-card purchases, cards **issued through Nyxi**, and pending or declined activity delivered through verified Fluz webhooks. The app checks its webhook inbox while open; background OS push notifications when the app is closed are not implemented.

**Fluz wallet funds are not a connected Chase checking or savings balance.** Banking balances and savings figures remain unavailable until a provider explicitly supports them. Nyxi does not infer or invent amounts.

When enabled by the backend operator, Nyxi can request a Fluz virtual card with a chosen spending limit and a funding source from the Fluz wallet or an eligible, already-linked bank account. Issuance is disabled by default because some Fluz programs reserve or debit funds when cards are created. Eligible cards can request an Apple Wallet / Google Pay provisioning link. Card numbers and CVVs are not stored in Nyxi.

The app intentionally uses **Cupertino and Liquid Glass**, including desktop/mobile adaptive cards, navigation, and transaction panels. No Material app shell.

## iOS / TestFlight

The iOS runner uses bundle ID `dev.blossomvale.nyxi`. Before running the **Nyxi iOS / TestFlight** workflow, register this bundle ID and create the Nyxi iOS app record in App Store Connect. Create an **App Store Connect distribution** provisioning profile for the same bundle ID and an active Apple Distribution certificate on team `7H8MNYGZ49`.

Set these repository Actions secrets before dispatching the workflow:

- `BUILD_CERTIFICATE_BASE64`: base64 of the Apple Distribution `.p12` that includes its private key.
- `P12_PASSWORD`: the `.p12` export password.
- `BUILD_PROVISION_PROFILE_BASE64`: base64 of the Nyxi `.mobileprovision` file.
- `APPSTORE_ISSUER_ID`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_PRIVATE_KEY`: the App Store Connect team issuer, matching key ID, and full `.p8` contents.

The workflow checks that the profile matches Nyxi, exports a signed IPA, and submits it to TestFlight. Never commit the signing files or paste their contents into chat.

## Tests

```bash
flutter analyze
flutter test
```

Flutter UI tests use a fake Nyxi backend; they never issue real cards. Backend Node tests and container build checks now live in [nyxi-backend](https://github.com/kawaiiepic/nyxi-backend).

## Security and production readiness

This is a developer integration preview. Fluz permissions, OAuth endpoints, webhooks, wallet provisioning, account funding and card issuance require end-to-end verification on a real approved Fluz integration before production use. Hardening includes verified signups, audit logging, durable rate limits, monitoring, backups, credential rotation and compliance review.

Do not commit or put your Fluz API keys, OAuth secrets, database, or encryption master key in this Flutter repository.
