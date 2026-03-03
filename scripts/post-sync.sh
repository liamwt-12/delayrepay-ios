#!/bin/bash
# This script runs after 'npx cap sync ios' to add native Swift files and entitlements

NATIVE_DIR="ios-native"
APP_DIR="ios/App/App"

echo "Copying native Swift plugins..."
cp "$NATIVE_DIR/AppleSignInPlugin.swift" "$APP_DIR/"
cp "$NATIVE_DIR/StoreKitPlugin.swift" "$APP_DIR/"

echo "Copying entitlements..."
cp "$NATIVE_DIR/App.entitlements" "$APP_DIR/"

echo "Native files copied successfully"
