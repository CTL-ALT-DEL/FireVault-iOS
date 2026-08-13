#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
derived_dir=$(mktemp -d /tmp/FireVault-verify.XXXXXX)
trap 'rm -rf "$derived_dir"' EXIT

cd "$repo_dir"

xcodebuild \
  -project FireVault.xcodeproj \
  -scheme FireVault \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_dir" \
  CODE_SIGNING_ALLOWED=NO \
  build

test_destination=${FIREVAULT_TEST_DESTINATION:-'platform=iOS Simulator,name=iPhone 17 Pro'}
xcodebuild \
  -project FireVault.xcodeproj \
  -scheme FireVault \
  -destination "$test_destination" \
  -derivedDataPath "$derived_dir" \
  -only-testing:FireVaultTests \
  test

xcodebuild \
  -project FireVault.xcodeproj \
  -scheme FireVault \
  -destination "$test_destination" \
  -derivedDataPath "$derived_dir" \
  -only-testing:FireVaultUITests/FireVaultUITests/testWarmIvorySettingsVisualReference \
  -only-testing:FireVaultUITests/FireVaultUITests/testSettingsRemainReachableAtAccessibilityTextSize \
  test
