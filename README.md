# DelayRepay iOS

iOS app for DelayRepay - UK Train Delay Compensation.

## Build

Builds are automated via Codemagic CI/CD. Push to `main` to trigger a build.

## Structure

- `www/` - Web assets (placeholder, app loads from https://delayrepay.uk)
- `ios-native/` - Native Swift plugins (copied into iOS project during build)
  - `AppleSignInPlugin.swift` - Sign in with Apple
  - `StoreKitPlugin.swift` - In-App Purchase via StoreKit 2
  - `App.entitlements` - App capabilities
- `resources/` - App icon (1024x1024 PNG)
- `codemagic.yaml` - CI/CD configuration
- `scripts/` - Build scripts
