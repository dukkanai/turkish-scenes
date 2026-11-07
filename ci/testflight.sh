#!/bin/bash
# Runs only on an ephemeral GitHub-hosted macOS runner.
set -euo pipefail
set +x
umask 077
PRIVATE_DIR="$(mktemp -d "$RUNNER_TEMP/turkish-signing.XXXXXX")"
KEYCHAIN="$PRIVATE_DIR/build.keychain-db"
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$PROFILE_DIR/77d42d0a-3dcc-4066-b825-109ef906a4cb.mobileprovision"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -f "$PROFILE_PATH"
  rm -rf "$PRIVATE_DIR"
}
trap cleanup EXIT
export PRIVATE_DIR
python3 - <<'PY'
import os, base64, pathlib, hashlib
p=pathlib.Path(os.environ["PRIVATE_DIR"])
for env,name in [
 ("TURKISH_DISTRIBUTION_P12_B64","distribution.p12"),
 ("TURKISH_APP_STORE_PROFILE_B64","profile.mobileprovision"),
 ("TURKISH_ASC_PRIVATE_KEY_B64","AuthKey_9X6UGZYBYR.p8")]:
 data=base64.b64decode(os.environ[env], validate=True)
 (p/name).write_bytes(data)
 if name=="profile.mobileprovision":
  assert hashlib.sha256(data).hexdigest()=="45d829c271268c7a59b243a5edbbbd9643dba6caff8133b9ce4923814fe053a1"
PY
security cms -D -i "$PRIVATE_DIR/profile.mobileprovision" > "$PRIVATE_DIR/profile.plist"
python3 - <<'PY'
import os, pathlib, plistlib, datetime
p=plistlib.loads((pathlib.Path(os.environ["PRIVATE_DIR"])/"profile.plist").read_bytes())
assert p["UUID"]=="77d42d0a-3dcc-4066-b825-109ef906a4cb"
assert p["Entitlements"]["application-identifier"]=="9G7GPBG7FB.dev.nextaura.turkishscenes"
assert not p["Entitlements"].get("get-task-allow",False)
assert "ProvisionedDevices" not in p
assert p["ExpirationDate"] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
PY
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$PRIVATE_DIR/distribution.p12" -P "$TURKISH_DISTRIBUTION_P12_PASSWORD" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
mkdir -p "$PROFILE_DIR"
cp "$PRIVATE_DIR/profile.mobileprovision" "$PROFILE_PATH"
BUILD_NUMBER="$GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT"
xcodebuild -project TurkishScenes.xcodeproj -scheme TurkishScenes -configuration Release -destination 'generic/platform=iOS' -archivePath build/TurkishScenes.xcarchive DEVELOPMENT_TEAM=9G7GPBG7FB CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER=turkish_scenes_app_store_20261101 CURRENT_PROJECT_VERSION="$BUILD_NUMBER" OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" archive
python3 ci/check_app_bundle.py build/TurkishScenes.xcarchive/Products/Applications/TurkishScenes.app
python3 - <<'PY'
import plistlib
with open("build/ExportOptions.plist","wb") as f:
 plistlib.dump({"method":"app-store-connect","destination":"export","teamID":"9G7GPBG7FB","signingStyle":"manual","signingCertificate":"Apple Distribution","provisioningProfiles":{"dev.nextaura.turkishscenes":"turkish_scenes_app_store_20261101"},"manageAppVersionAndBuildNumber":False,"testFlightInternalTestingOnly":True,"uploadSymbols":True}, f)
PY
xcodebuild -exportArchive -archivePath build/TurkishScenes.xcarchive -exportOptionsPlist build/ExportOptions.plist -exportPath build/export
IPA="build/export/TurkishScenes.ipa"
test -s "$IPA"
codesign --verify --deep --strict build/TurkishScenes.xcarchive/Products/Applications/TurkishScenes.app
export API_PRIVATE_KEYS_DIR="$PRIVATE_DIR"
python3 ci/run_altool.py validate --type ios --file "$IPA" --apiKey 9X6UGZYBYR --apiIssuer 54a3742f-c62d-468e-a2ae-70e0d8aff797
# Exactly one upload attempt. An uncertain upload must be checked in ASC before retry.
python3 ci/run_altool.py upload --type ios --file "$IPA" --apiKey 9X6UGZYBYR --apiIssuer 54a3742f-c62d-468e-a2ae-70e0d8aff797
printf 'Apple explicitly confirmed upload for build %s. Processing and tester availability still require verification.\n' "$BUILD_NUMBER"

# Read the exact uploaded build; never retry the upload because processing is pending.
export TURKISH_EXPECTED_BUILD="$BUILD_NUMBER"
ruby ci/verify_testflight.rb
