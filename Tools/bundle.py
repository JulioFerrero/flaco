"""Writes Flaco's Info.plist, icons and launch images into the app bundle.

usage: python3 bundle.py <Flaco.app> <icon-1024.png> <iPhoneOS|iPhoneSimulator> <bundle id>
"""
import plistlib
import sys

from PIL import Image

app, icon, platform, bundle_id = sys.argv[1:5]
source = Image.open(icon).convert("RGB")
for name, px in [("Icon-60@2x.png", 120), ("Icon-60@3x.png", 180), ("Icon-40@2x.png", 80), ("Icon-40@3x.png", 120),
                 ("Icon-29@2x.png", 58), ("Icon-29@3x.png", 87)]:
    source.resize((px, px), Image.LANCZOS).save(f"{app}/{name}")
# Launch images at the 5c's and 6s's sizes, so iOS 10 runs the app at full size rather than letterboxed.
# iOS 14 and later read UILaunchScreen instead.
Image.new("RGB", (640, 1136), (16, 16, 16)).save(f"{app}/Default-568h@2x.png")
Image.new("RGB", (750, 1334), (16, 16, 16)).save(f"{app}/Default-667h@2x.png")
info = {
    "CFBundleIdentifier": bundle_id,
    "CFBundleExecutable": "Flaco",
    "CFBundleName": "Flaco",
    "CFBundleDisplayName": "Flaco",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "2.0",
    "CFBundleVersion": "1",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleDevelopmentRegion": "en",
    "CFBundleSupportedPlatforms": [platform],
    "DTPlatformName": platform.lower(),
    "MinimumOSVersion": "10.0",
    "LSRequiresIPhoneOS": True,
    "UIDeviceFamily": [1],
    "UIRequiredDeviceCapabilities": ["armv7"],
    "UIStatusBarStyle": "UIStatusBarStyleLightContent",
    "UIViewControllerBasedStatusBarAppearance": False,
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    "UIBackgroundModes": ["audio"],
    "UIFileSharingEnabled": True,
    "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["Icon-29", "Icon-40", "Icon-60"]}},
    "UILaunchImages": [
        {"UILaunchImageName": "Default-568h", "UILaunchImageSize": "{320, 568}",
         "UILaunchImageMinimumOSVersion": "7.0", "UILaunchImageOrientation": "Portrait"},
        {"UILaunchImageName": "Default-667h", "UILaunchImageSize": "{375, 667}",
         "UILaunchImageMinimumOSVersion": "8.0", "UILaunchImageOrientation": "Portrait"},
    ],
    "UILaunchScreen": {},
}
with open(f"{app}/Info.plist", "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
with open(f"{app}/PkgInfo", "w") as f:
    f.write("APPL????")
