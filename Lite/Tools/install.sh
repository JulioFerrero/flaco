#!/bin/sh
# Signs build/Payload/FlacoLite.app and installs it on the connected iOS 10 phone.
#
# Today's Xcode can't talk to iOS 10 phones, but it still makes the profile: a placeholder app with Flaco
# Lite's bundle id, built for any iOS device, gets the team's profile, which lists every phone registered
# with the team. (The 5c was registered once with xtool.) The certificate is Xcode's own, so nothing is
# revoked. With a free account the profile lasts 7 days; run this again to renew it.
set -e
cd "$(dirname "$0")/.."
APP=build/Payload/FlacoLite.app
[ -d $APP ] || ./build.sh
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' ../Config/Local.xcconfig)
BUNDLE=$(plutil -extract CFBundleIdentifier raw $APP/Info.plist)
WORK=build/signing
rm -rf $WORK && mkdir -p $WORK/App
echo 'int main(void) { return 0; }' > $WORK/App/main.c
cat > $WORK/project.yml <<YML
name: FlacoLiteSigning
targets:
  Placeholder:
    type: application
    platform: iOS
    deploymentTarget: "15.0"
    sources: [App]
    settings:
      PRODUCT_NAME: FlacoLite
      PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE
      DEVELOPMENT_TEAM: $TEAM
      CODE_SIGN_STYLE: Automatic
      GENERATE_INFOPLIST_FILE: YES
YML
(cd $WORK && xcodegen generate -q)
xcodebuild -project $WORK/FlacoLiteSigning.xcodeproj -scheme Placeholder -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath $WORK/dd -allowProvisioningUpdates -quiet build
PLACEHOLDER=$WORK/dd/Build/Products/Release-iphoneos/FlacoLite.app
IDENTITY=$(codesign -dvv $PLACEHOLDER 2>&1 | sed -n 's/^Authority=\(Apple Development: .*\)/\1/p')
codesign -d --entitlements - --xml $PLACEHOLDER > $WORK/entitlements.plist

SIGNED=$WORK/FlacoLite.app
cp -R $APP $SIGNED
cp $PLACEHOLDER/embedded.mobileprovision $SIGNED/
codesign -f -s "$IDENTITY" --entitlements $WORK/entitlements.plist --generate-entitlement-der $SIGNED

# The phone on iOS 10, if more than one is plugged in.
UDID=""
for id in $(idevice_id -l); do
  case "$(ideviceinfo -u $id -k ProductVersion)" in 10.*) UDID=$id ;; esac
done
[ -n "$UDID" ] || { echo "No iOS 10 phone connected"; exit 1; }
ideviceinstaller -u $UDID install $SIGNED
security cms -D -i $SIGNED/embedded.mobileprovision | plutil -extract ExpirationDate raw - | sed 's/^/Signed until /'
