#!/bin/bash
# post-sync.sh — Copies native plugin files into the Capacitor iOS project
# Run after `npx cap sync ios` during Codemagic build

set -e

APP_DIR="ios/App/App"

echo "[post-sync] Copying native plugin files to $APP_DIR..."

# Copy Swift plugin implementations
cp ios-native/AppleSignInPlugin.swift "$APP_DIR/AppleSignInPlugin.swift"
cp ios-native/StoreKitPlugin.swift "$APP_DIR/StoreKitPlugin.swift"

# Copy Objective-C plugin registration macros
cp ios-native/AppleSignInPlugin.m "$APP_DIR/AppleSignInPlugin.m"
cp ios-native/StoreKitPlugin.m "$APP_DIR/StoreKitPlugin.m"

# Copy entitlements
cp ios-native/App.entitlements "$APP_DIR/App.entitlements"

echo "[post-sync] Done — all native files copied."
