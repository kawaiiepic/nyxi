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

## Liquid Glass UI

Nyxi uses [liquid_glass_widgets](https://pub.dev/packages/liquid_glass_widgets)
for real shader-based iOS-style navigation glass. The pastel background is
sampled by `GlassPage`, the floating navigation is `GlassTabBar.bottom`,
the card-freeze toggle is a `GlassSwitch`, and transaction/savings panels use
`GlassContainer.card(surfaceStyle: GlassSurfaceStyle.solid)` so account details
remain readable. The app uses `CupertinoApp` instead of Material.

Requires Flutter **3.41+**. The startup function preloads glass resources.
