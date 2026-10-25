#!/bin/sh
# Signs build/Payload/Flaco.app and installs it on every iPhone plugged in.
#
# Today's Xcode can't talk to iOS 10 phones, but it still makes the profile: a placeholder app with Flaco's
# bundle id, built for any iOS device, gets the team's profile, which lists every phone registered with the
# team. (The 5c was registered once with xtool; see docs/iphone-5c.md.) The certificate is Xcode's own, so
# nothing is revoked. With a free account the profile lasts 7 days; run this again to renew it.
set -e
cd "$(dirname "$0")/.."
APP=build/Payload/Flaco.app
[ -d $APP ] || ./build.sh
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig)
BUNDLE=$(plutil -extract CFBundleIdentifier raw $APP/Info.plist)
WORK=build/signing
rm -rf $WORK && mkdir -p $WORK/App
echo 'int main(void) { return 0; }' > $WORK/App/main.c
cat > $WORK/project.yml <<YML
name: FlacoSigning
targets:
  Placeholder:
    type: application
    platform: iOS
    deploymentTarget: "15.0"
    sources: [App]
    settings:
      PRODUCT_NAME: Flaco
      PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE
      DEVELOPMENT_TEAM: $TEAM
      CODE_SIGN_STYLE: Automatic
      GENERATE_INFOPLIST_FILE: YES
YML
(cd $WORK && xcodegen generate -q)
xcodebuild -project $WORK/FlacoSigning.xcodeproj -scheme Placeholder -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath $WORK/dd -allowProvisioningUpdates -quiet build
PLACEHOLDER=$WORK/dd/Build/Products/Release-iphoneos/Flaco.app
IDENTITY=$(codesign -dvv $PLACEHOLDER 2>&1 | sed -n 's/^Authority=\(Apple Development: .*\)/\1/p')
codesign -d --entitlements - --xml $PLACEHOLDER > $WORK/entitlements.plist

SIGNED=$WORK/Flaco.app
cp -R $APP $SIGNED
cp $PLACEHOLDER/embedded.mobileprovision $SIGNED/
codesign -f -s "$IDENTITY" --entitlements $WORK/entitlements.plist --generate-entitlement-der $SIGNED

PHONES=$(idevice_id -l)
[ -n "$PHONES" ] || { echo "No iPhone connected"; exit 1; }
for id in $PHONES; do
  echo "$(ideviceinfo -u $id -k DeviceName), iOS $(ideviceinfo -u $id -k ProductVersion)"
  ideviceinstaller -u $id install $SIGNED | tail -1
done
security cms -D -i $SIGNED/embedded.mobileprovision | plutil -extract ExpirationDate raw - | sed 's/^/Signed until /'
