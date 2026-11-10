# Intent iOS app

The native SwiftUI rewrite of the web frontend (`artifacts/traintent`). The backend
(Express API on Vercel, Neon, Clerk, `lib/api-spec/openapi.yaml`) is unchanged. The
user-facing name is **Intent**, never Trainient.

## Layout

```
ios/
  Package.swift, xtool.yml      xtool (WSL) view of the app: one library product "Intent"
  project.yml                   XcodeGen view of the app, used on the CI Mac
  Sources/Intent/               the app target
    IntentApp.swift             entry: registers fonts, creates AppServices
    AppServices.swift           the ONE AuthSession + IntentAPIClient (mock-aware)
    DebugScreen.swift/RootView  -IntentScreen <name> opens any screen directly
    Shell/                      AppRootView (sign-in → onboarding gate → tabs), MainTabView
    Features/<Feature>/         one folder per screen family (Dashboard, Program, Log, ...)
  Packages/IntentKit/           local SwiftPM package
    IntentCore                  pure logic ported from web src/lib, Foundation only,
                                parity-tested against the TS (Linux + macOS)
    IntentDesign                Sessions design system: Color.intent.*, .intentText(),
                                IntentPage/Card/buttons/option cards/grouped lists/tab bar
    IntentAPI                   generated OpenAPI client + IntentAPIClient facade
                                + FixtureTransport (mock backend) + Fixtures/<scenario>/
    IntentAuth                  Clerk (clerk-ios) behind AuthSession / SignInView
  scripts/
    sim.sh                      drive the CI simulator from Windows (see below)
    phone.sh                    install the CI-built ipa on the iPhone via xtool
    generate-api.sh             regenerate IntentAPI/Generated from openapi.yaml
    core-fixtures/              regenerate IntentCore parity fixtures from the TS
    mock-fixtures/              regenerate the shared mock-backend fixtures
    ci/                         what the GitHub macOS runner executes
```

## Building and seeing the app (no Mac needed)

GitHub Actions (macos-latest) is the Mac. The main repo is private and macOS minutes
cost 10x there, so CI runs in the public mirror **jafr03002/intent-ios**, which holds
only `ios/` (no backend, no AI skills): `.github/workflows/ios-mirror.yml` copies `ios/`
there on every push, and `ios/ci/ios-simulator.yml` becomes that repo's workflow. Every
push touching `ios/` runs: IntentKit tests → simulator build → screenshots of **every
feature screen** in mock mode → unsigned device ipa. Results come back as the `ios-sim`
artifact (`summary.md`, `screens/<name>.png`, `build.log`, `os-log.txt`, `crashes/`).

```
git push && bash ios/scripts/sim.sh            # wait for the push run of HEAD, download to ios/out-ci
bash ios/scripts/sim.sh --screens log,start    # dispatch a run with chosen screens (faster: no ipa)
bash ios/scripts/sim.sh --screens dashboard --scenario calibration   # another fixture scenario
bash ios/scripts/sim.sh --screens home --mock 0                      # real API + real sign-in screen
bash ios/scripts/sim.sh --run <id>             # fetch an existing run
```

A run takes ~6-12 minutes; tools with a 10-minute command limit should run `sim.sh` in
the background. Read the PNGs to check your work.

Linux tests (WSL, Swift 6.4): `cd ios/Packages/IntentKit && swift test --scratch-path /tmp/ik`.
IntentDesign compiles empty on Linux (`#if canImport(SwiftUI)`); IntentAuth runs signed-out.

Real iPhone: `bash ios/scripts/phone.sh` downloads the CI ipa and `xtool install`s it
(free Apple ID; apps expire after 7 days). `xtool dev build` does NOT work for this app:
Clerk's .xcstrings/.xcassets need Apple tools.

## Mock backend

`-IntentMock` (default on CI) swaps the network for `FixtureTransport`: each API call is
answered from `Packages/IntentKit/Sources/IntentAPI/Fixtures/<scenario>/<operationID>.json`
(falling back to `default/`), format `{"status": 200, "body": ...}`. Date tokens keep data
relative to today: `{{date:-3}}`, `{{datetime:0}}`, `{{dow:mon:-1}}` (Monday last week),
`{{dowtime:fri:0}}`. A missing fixture answers 404 so gaps are visible.

The default user "Alex" (AI mode, gain_weight, 4-day Upper/Lower Mon/Tue/Thu/Fri, week 3
of an 8-week bulk, history for weeks 1-2 + this Monday) comes from
`scripts/mock-fixtures/make_default.py`. Every fixture must decode through the generated
client: add a call for it in `Tests/IntentAPITests/FixtureTransportTests.swift`.
Writes (POST/PATCH) are stateless: they return their fixture and change nothing.

## Conventions

- Swift 6 language mode, iOS 17+, iPhone portrait, dark only.
- **Style: Sessions** (`TrainientAppDesign.md`, web `src/theme/tokens.ts`): pure black,
  grey rounded cards, thin/light Inter, white-on-black selection, one teal accent
  (`Color.intent.sessionsCyan`), no glows, no colour shadows. Use IntentDesign components;
  add to IntentDesign only when a pattern is reused across features.
- Port behaviour faithfully from the web page you are replacing; pure logic belongs in
  IntentCore (with parity tests), view state in the feature folder. If the web has a bug,
  port it and list it - don't silently fix it in one client.
- Screens read services with `@Environment(AppServices.self)`; API via
  `services.api.api.<operation>()`. Never create another `AuthSession`.
- Every screen family has a `DebugScreen` case so CI screenshots it; add variants
  (e.g. `log-finished`) for states worth seeing.
- Helpers that map API types to IntentCore models live in the feature folder and are
  `fileprivate` or feature-prefixed, to avoid duplicate-symbol clashes between features.
