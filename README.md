# Nyxi

A cybercute personal-finance app built with Flutter.

Nyxi starts with a polished, interactive demo home screen inspired by the supplied pink money-app reference. All amounts are **demo data**; no banking or card provider is connected.

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
- All views share one in-memory demo state, so balances and card controls
  survive resizing, but reset when the app restarts.

## Klutch integration (personal developer preview)

Nyxi can now read **real Klutch cards**, display **recent transactions**, and
**issue virtual cards** through an opt-in local gateway. Demo balances, demo
transfers, and demo card-freeze controls are **not** Klutch account actions.

Klutch documents a GraphQL production endpoint, a sandbox endpoint, and a
`createSessionToken(clientId, secretKey)` authentication mutation.
Documentation: https://api-docs.klutchcard.com/

### Start the private local gateway

1. Sign into Klutch and open **My Account → Developers** to obtain a personal
   `clientId` and `secretKey`. Do not put these in the Flutter app, Git, or
   `--dart-define`.
2. Set the following variables in your **terminal**, not in source code:

   ```bash
   export KLUTCH_CLIENT_ID='your-client-id'
   export KLUTCH_SECRET_KEY='your-secret-key'
   export KLUTCH_ENV='production'
   export NYXI_GATEWAY_TOKEN="$(openssl rand -hex 32)"
   printf 'Nyxi gateway token: %s\n' "$NYXI_GATEWAY_TOKEN"
   node gateway/server.mjs
   ```

   For a registered Mini App development environment, set
   `KLUTCH_ENV=sandbox` if Klutch has granted you sandbox credentials.
   A personal Klutch API key is intended for production.

3. In another terminal, run `flutter run -d linux` (or your target device).
4. Open **Cards → Connect Klutch** and paste **NYXI_GATEWAY_TOKEN**, not your
   Klutch secret. For a running terminal, copy the token from the variable
   you created in step 2.
5. Nyxi retrieves card metadata and recent transactions only after you
   explicitly connect. Click **Create virtual card** to confirm a real issuance.

The gateway binds to **127.0.0.1:8787 only**, requires a long independent
access token, and keeps the Klutch developer secret server-side. Its data is
never saved to disk. The Flutter app holds the gateway token only in memory
until the current session ends. It does not request, render, or cache full
card numbers or CVV.

When running on an Android emulator, start the gateway on a reachable trusted
interface **only after** securing its transport, then compile with
`--dart-define=NYXI_KLUTCH_URL=https://your-secure-gateway.example`. An emulator
normally uses `10.0.2.2` for the host, but the default gateway is loopback
only and is not reachable from it. Do not publish or port-forward the local
gateway as-is.

### Current limitations

- This is a **single-user personal integration**, not an approved Nyxi
  multi-user Klutch Mini App. Other people's accounts will require Klutch
  Mini App enrollment, permissioned per-user authentication, and a production
  service that isolates accounts and data.
- The desktop/mobile demo card-freeze toggle has **no effect** on Klutch.
  Real card locking, rule creation, card-number reveal, webhooks, and
  background synchronization are not implemented.
- Only the first 30 recent Klutch transactions are shown. They do not change
  Nyxi's fictional cash and savings amounts.
- The gateway's Node.js tests use a fake Klutch server and can run with
  `node --test gateway/server.test.mjs`. Live Klutch account testing requires
  your own credentials and explicit authorization.

## Liquid Glass UI

Nyxi uses [liquid_glass_widgets](https://pub.dev/packages/liquid_glass_widgets)
for real shader-based iOS-style navigation glass. The pastel background is
sampled by `GlassPage`, the floating navigation is `GlassTabBar.bottom`,
the card-freeze toggle is a `GlassSwitch`, and transaction/savings panels use
`GlassContainer.card(surfaceStyle: GlassSurfaceStyle.solid)` so account details
remain readable. The app uses `CupertinoApp` instead of Material.

Requires Flutter **3.41+**. The startup function preloads glass resources.
