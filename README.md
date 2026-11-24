# Nyxi ✦

A cybercute Flutter finance dashboard with Cupertino, `liquid_glass_widgets`, and an authenticated Cloudflare Worker backend. No demo mode, fictional balances, transactions, cards, or guest sign-in.

## Repositories

- **Flutter app:** [kawaiiepic/nyxi](https://github.com/kawaiiepic/nyxi) (this repository)
- **Cloudflare Worker + D1:** [kawaiiepic/petal-backend](https://github.com/kawaiiepic/petal-backend) (private)
- **Legacy VPS backend:** [kawaiiepic/nyxi-backend](https://github.com/kawaiiepic/nyxi-backend) (migration reference only)

The app now connects to the shared Petal Worker under `/nyxi`, with separate Nyxi accounts and encrypted Fluz credentials. No VPS, Docker or Traefik is needed for the API. Registration is enabled by default. The public landing page is independent of this API.

## Run Flutter

```bash
flutter create --platforms=android,ios,linux,windows .
flutter pub get
flutter run -d linux
```

Flutter 3.41+ is required. Platform runner directories are generated locally. The API origin is hardcoded in `lib/fluz_gateway.dart` to **`https://petal-backend.blossomvale.dev/nyxi`** on all platforms; no `--dart-define` is needed. Your backend must be reachable via **HTTPS** from the device. For development only, Nyxi also allows `localhost`, `127.0.0.1`, and Android emulator `10.0.2.2` over plain HTTP. Android/iOS devices cannot use the Linux desktop's `127.0.0.1`; use your backend HTTPS hostname.

Use the [Worker deployment guide](https://github.com/kawaiiepic/petal-backend/blob/main/docs/nyxi.md) to deploy migrations, configure Cloudflare secrets and update Fluz OAuth and webhook URLs. Old VPS accounts are not transferred automatically.

## Backend setup (Cloudflare)

The API is hosted by the shared `petal-backend` Worker; there is no separate Nyxi server to install.

1. Clone the private `petal-backend` repository and run `npm ci`.
2. Authenticate with `npx wrangler login` and configure the Worker resources and existing Petal secrets as described in its README.
3. Run `npm run deploy` to apply D1 migrations, including `0031_nyxi.sql`, and deploy the Worker.
4. Verify `curl -fsS https://petal-backend.blossomvale.dev/nyxi/health` returns `{"status":"ok","service":"nyxi-api"}`.
5. Open Nyxi, choose **Create an account**, enter your email and a 12–128 character password, and sign in. Fluz credentials are not needed to register.

To connect Fluz, configure `NYXI_ENCRYPTION_KEY` (64 hexadecimal characters) and the appropriate Fluz credentials using `npx wrangler secret put NAME`. For OAuth, register these exact URLs with Fluz:

| Purpose | URL |
| --- | --- |
| API | `https://petal-backend.blossomvale.dev/nyxi` |
| OAuth callback | `https://petal-backend.blossomvale.dev/nyxi/api/fluz/callback` |
| Webhook | `https://petal-backend.blossomvale.dev/nyxi/api/fluz/webhook` |

See the [full setup guide](https://github.com/kawaiiepic/petal-backend/blob/main/docs/nyxi.md) for OAuth and personal API-key mode. Registration does not verify email ownership or open a bank account. Keep card issuance disabled until the integration has been reviewed and tested.

**Migration status:** The new architecture is in source control; deployment and live Fluz verification are separate steps. Existing VPS accounts and financial records are not automatically imported. Keep the old SQLite database and encryption key backed up until migration is verified. Do not expose them publicly.

## Account and Fluz connection

- Nyxi requires a valid authenticated central-backend session. No guest, offline, or demo-only access.
- On startup, and approximately every 12 seconds while the app is ready, it checks `GET /nyxi/health` and `GET /nyxi/api/auth/me`. An unresponsive or invalid backend locks the dashboard until authentication and health recover.
- Sessions are held in memory only. Restarting Nyxi requires signing in again.
- **OAuth mode:** In **Cards → Connect Fluz**, Nyxi opens Fluz's authorization page. The backend handles the callback, stores encrypted tokens, and connects the correct Nyxi account.
- **Single-account API-key mode:** Set `FLUZ_AUTH_MODE=api_key`, `FLUZ_API_KEY`, `FLUZ_USER_ID`, `FLUZ_ACCOUNT_ID`, and `NYXI_FLUZ_OWNER_USER_ID` as Worker bindings and secrets. The designated Nyxi login automatically shows Fluz as server-managed, without an OAuth popup. The key is **never entered in Flutter** and is not shared with other Nyxi accounts. See the [backend API-key setup guide](https://github.com/kawaiiepic/petal-backend/blob/main/docs/nyxi.md).
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

The workflow checks that the profile matches Nyxi, exports a signed IPA, submits it to TestFlight and waits for Apple processing. The iOS Info.plist and upload action declare exempt encryption; verify this declaration against all bundled dependencies before distributing.

Before uploading, complete App Store Connect → Nyxi → TestFlight → Test Information with a beta description, a real tester feedback email, and the primary locale. Alternatively, set the `TESTFLIGHT_FEEDBACK_EMAIL` repository secret and the repository Actions variable `NYXI_CONFIGURE_TESTFLIGHT_INFO` to `true`. The next upload workflow will use the pinned Apple Actions metadata helper to create or update the English (US) Test Information before building. Disable that variable after setup to avoid overwriting manually edited information on subsequent releases. The feedback address is visible to testers. If the primary app locale is not English (US), use the App Store Connect UI to configure the correct locale instead.

Never commit the signing files or paste their contents into chat.

## Tests

```bash
flutter analyze
flutter test
```

Flutter UI tests use a fake Nyxi backend; the gateway test also checks the `/nyxi` request prefix using a local HTTP server. They never issue real cards. Backend Worker code lives in [petal-backend](https://github.com/kawaiiepic/petal-backend).

## Security and production readiness

This is a developer integration preview. Fluz permissions, OAuth endpoints, webhooks, wallet provisioning, account funding and card issuance require end-to-end verification on a real approved Fluz integration before production use. Hardening includes verified signups, audit logging, durable rate limits, monitoring, backups, credential rotation and compliance review.

Do not commit or put your Fluz API keys, OAuth secrets, database, or encryption master key in this Flutter repository.
