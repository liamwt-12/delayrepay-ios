#!/bin/bash
# This script runs after 'npx cap sync ios' to add native Swift files and entitlements

NATIVE_DIR="ios-native"
APP_DIR="ios/App/App"

echo "Copying native Swift plugins..."
cp "$NATIVE_DIR/AppleSignInPlugin.swift" "$APP_DIR/"
cp "$NATIVE_DIR/StoreKitPlugin.swift" "$APP_DIR/"

echo "Copying entitlements..."
cp "$NATIVE_DIR/App.entitlements" "$APP_DIR/"

echo "Registering Swift files in Xcode project..."
gem install xcodeproj --quiet
ruby << 'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
target = project.targets.first
group = project.main_group['App']
['StoreKitPlugin.swift', 'AppleSignInPlugin.swift'].each do |file|
  unless group.files.map(&:path).include?(file)
    ref = group.new_file(file)
    target.source_build_phase.add_file_reference(ref)
    puts "Added #{file}"
  end
end
project.save
RUBY

echo "Native files registered successfully"
