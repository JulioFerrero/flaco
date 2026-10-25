# Building for the iPhone 5c

The iPhone 5c has a 32-bit A6 and stops at iOS 10.3.3. Today's Xcode doesn't support either, but its compiler still builds for the A6 (`armv7s`), and an Objective-C app that only calls what iOS 10 has runs fine. This is how Flaco gets there.

## Build

```sh
Lite/build.sh        # build/FlacoLite.ipa, for the phone
Lite/build.sh sim    # build/sim/FlacoLite.app, for the simulator
```

No Xcode project: `build.sh` calls `clang` directly. Three things make it work:

- **Library stubs with `armv7s` in them.** The SDK's `.tbd` stubs only list `arm64e` now. `Tools/stubs.py` copies them to `build/stubs`, adds `armv7s` to every target list, and adds the few symbols only 32-bit ARM needs: `objc_msgSend_stret`, the `_Unwind_SjLj_*` functions that `@synchronized` and `__weak` use, and `__divdi3` and the other 64-bit arithmetic helpers, which live in libSystem on 32-bit iPhones.
- **All ARM code, no Thumb (`-marm`).** Today's linker leaves the Thumb bit off the entry point and off pointers to Thumb functions, so iOS 10 runs Thumb code as ARM and crashes on the first call.
- **Only what iOS 10 has.** The stubs come from a newer SDK, so the linker can't catch a call to something newer, and the app would then crash at launch. Check the imports before installing: `xcrun nm -m -u build/Payload/FlacoLite.app/FlacoLite`. Newer APIs are reached with `respondsToSelector:` and `valueForKey:`, never linked directly.

FLAC is decoded by [dr_flac](https://github.com/mackron/dr_libs), in `Vendor/`, since iOS 10 has no FLAC decoder.

## Register the phone once

Today's Xcode can't see iOS 10 phones, so it can't add the 5c to the team. [xtool](https://github.com/xtool-org/xtool) can, through the same Apple sign-in Xcode uses:

```sh
xtool auth login -m password
xtool install Lite/build/FlacoLite.ipa
```

`xtool install` registers the phone first, then asks to revoke the team's development certificates so it can make its own. **Answer no**: those certificates sign the other apps on your phones. The phone is registered by then.

In October 2026 Apple refused sign-ins from tools like this (errors -80046, then 503). xtool 1.23.0 fixed the first; the second needed [xtool#405](https://github.com/xtool-org/xtool/pull/405), built from source with `swift build -c release --product xtool`.

## Sign and install

```sh
Lite/Tools/install.sh
```

Xcode still makes the profile: the script builds a placeholder app with Flaco Lite's bundle id for any iOS device, and the team's profile lists every registered phone. It signs with Xcode's own certificate, then installs with `ideviceinstaller`. With a free account the profile lasts 7 days; run the script again to renew it.

## On the phone

- **Music:** Finder → the iPhone → Files → Flaco Lite. Or from the terminal:
  `afcclient --container dev.julio.flacolite -- put -rf "Album" "/Documents/Album"`
- **Crash reports:** `idevicecrashreport -k -e reports/`, then `xcrun atos -o build/Payload/FlacoLite.app/FlacoLite -arch armv7s -l <load address> <address>`.
- **Screenshots** need the iOS 10.3 developer disk image, which today's Xcode doesn't ship. The phone checks Apple's signature before mounting it:
  `ideviceimagemounter mount DeveloperDiskImage.dmg DeveloperDiskImage.dmg.signature`, then `idevicescreenshot`. It's unmounted again when the phone restarts.

## Trying it in the simulator

Simulator builds take launch options, so Flaco Lite can be tried without touching it: `xcrun simctl launch <device> dev.julio.flacolite -FLPlay 3 -FLSeek 60 -FLMute YES -FLTab 1`.
