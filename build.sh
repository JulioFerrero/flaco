#!/bin/sh
# Builds Flaco: `./build.sh` for iPhones as build/Flaco.ipa, one app for both the iPhone 5c (armv7s, iOS 10)
# and the 6s (arm64); `./build.sh sim` for the simulator as build/sim/Flaco.app.
#
# Today's Xcode no longer builds for 32-bit iPhones, but its compiler still does. Only its library stubs lack
# armv7s, so the phone build links against a copy made by Tools/stubs.py (build/stubs, made once).
# See docs/iphone-5c.md.
set -e
cd "$(dirname "$0")"
FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AudioToolbox
  -framework AVFoundation -framework MediaPlayer -framework Accelerate -framework ImageIO -framework Security"
SOURCES="Sources/*.m Vendor/dr_flac.c"
FLAGS="-fobjc-arc -O2 -Wall -Wno-unused-function -ISources -IVendor"
BUNDLE_ID=$(sed -n 's/^FLACO_BUNDLE_ID *= *//p' Config/Local.xcconfig 2>/dev/null)

if [ "$1" = sim ]; then
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  APP=build/sim/Flaco.app
  rm -rf build/sim && mkdir -p $APP
  xcrun -sdk iphonesimulator clang -target arm64-apple-ios12.0-simulator -isysroot "$SDK" $FLAGS $FRAMEWORKS $SOURCES -o $APP/Flaco
  PLATFORM=iPhoneSimulator
else
  SDK=$(xcrun --sdk iphoneos --show-sdk-path)
  STUBS=build/stubs
  [ -f $STUBS/usr/lib/libobjc.A.tbd ] || python3 Tools/stubs.py "$SDK" $STUBS
  APP=build/Payload/Flaco.app
  rm -rf build/Payload build/obj && mkdir -p $APP
  SLICES=""
  # -marm on armv7s: today's linker doesn't set the Thumb bit on the entry point or on pointers to Thumb
  # functions, so iOS 10 would run Thumb code as ARM. All-ARM code needs no such bit.
  for ARCH in armv7s arm64; do
    MODE=""
    [ $ARCH = armv7s ] && MODE=-marm
    mkdir -p build/obj/$ARCH
    OBJECTS=""
    for src in $SOURCES; do
      obj=build/obj/$ARCH/$(basename "$src").o
      xcrun -sdk iphoneos clang -arch $ARCH $MODE -miphoneos-version-min=10.0 -isysroot "$SDK" $FLAGS -c "$src" -o "$obj"
      OBJECTS="$OBJECTS $obj"
    done
    xcrun -sdk iphoneos clang -arch $ARCH -miphoneos-version-min=10.0 -isysroot $STUBS $FRAMEWORKS $OBJECTS -o build/obj/Flaco-$ARCH
    SLICES="$SLICES build/obj/Flaco-$ARCH"
  done
  lipo -create $SLICES -output $APP/Flaco
  PLATFORM=iPhoneOS
fi

BUNDLE_ID=${BUNDLE_ID:-dev.julio.flaco}
python3 Tools/bundle.py $APP Resources/icon-1024.png $PLATFORM $BUNDLE_ID
codesign -s - --force $APP
if [ "$1" != sim ]; then
  (cd build && rm -f Flaco.ipa && zip -qr Flaco.ipa Payload)
  echo build/Flaco.ipa
fi
