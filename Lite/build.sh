#!/bin/sh
# Builds Flaco Lite: `./build.sh` for the iPhone 5c (armv7s, iOS 10) as build/FlacoLite.ipa,
# `./build.sh sim` for the simulator as build/sim/FlacoLite.app.
#
# Today's Xcode no longer builds for 32-bit iPhones, but its compiler still does. Only its library stubs lack
# armv7s, so the device build links against a copy made by Tools/stubs.py (build/stubs, made once).
set -e
cd "$(dirname "$0")"
FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AudioToolbox
  -framework AVFoundation -framework MediaPlayer -framework Accelerate -framework ImageIO"
SOURCES="Sources/*.m Vendor/dr_flac.c"
FLAGS="-fobjc-arc -O2 -Wall -Wno-unused-function -ISources -IVendor"

if [ "$1" = sim ]; then
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  APP=build/sim/FlacoLite.app
  rm -rf build/sim && mkdir -p $APP
  xcrun -sdk iphonesimulator clang -target arm64-apple-ios12.0-simulator -isysroot "$SDK" $FLAGS $FRAMEWORKS $SOURCES -o $APP/FlacoLite
  PLATFORM=iPhoneSimulator
else
  SDK=$(xcrun --sdk iphoneos --show-sdk-path)
  STUBS=build/stubs
  [ -f $STUBS/usr/lib/libobjc.A.tbd ] || python3 Tools/stubs.py "$SDK" $STUBS
  APP=build/Payload/FlacoLite.app
  rm -rf build/Payload && mkdir -p $APP build/obj
  OBJECTS=""
  for src in $SOURCES; do
    obj=build/obj/$(basename "$src").o
    xcrun -sdk iphoneos clang -arch armv7s -miphoneos-version-min=10.0 -isysroot "$SDK" $FLAGS -c "$src" -o "$obj"
    OBJECTS="$OBJECTS $obj"
  done
  xcrun -sdk iphoneos clang -arch armv7s -miphoneos-version-min=10.0 -isysroot $STUBS $FRAMEWORKS $OBJECTS -o $APP/FlacoLite
  PLATFORM=iPhoneOS
fi

python3 Tools/bundle.py $APP ../Flaco/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png $PLATFORM
codesign -s - --force $APP
if [ "$1" != sim ]; then
  (cd build && rm -f FlacoLite.ipa && zip -qr FlacoLite.ipa Payload)
  echo build/FlacoLite.ipa
fi
