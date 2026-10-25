"""Writes Flaco Lite's Info.plist, icons and 4-inch launch image into the app bundle.

usage: python3 bundle.py <FlacoLite.app> <icon-1024.png> <iPhoneOS|iPhoneSimulator>
"""
import plistlib
import sys

from PIL import Image

app, icon, platform = sys.argv[1:4]
source = Image.open(icon).convert("RGB")
for name, px in [("Icon-60@2x.png", 120), ("Icon-40@2x.png", 80), ("Icon-29@2x.png", 58)]:
    source.resize((px, px), Image.LANCZOS).save(f"{app}/{name}")
# A launch image at the 5c's size, so iOS 10 runs the app at full height rather than letterboxed.
Image.new("RGB", (640, 1136), (16, 16, 16)).save(f"{app}/Default-568h@2x.png")
info = {
    "CFBundleIdentifier": "dev.julio.flacolite",
    "CFBundleExecutable": "FlacoLite",
    "CFBundleName": "Flaco Lite",
    "CFBundleDisplayName": "Flaco Lite",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1",
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
    "UILaunchImages": [{
        "UILaunchImageName": "Default-568h", "UILaunchImageSize": "{320, 568}",
        "UILaunchImageMinimumOSVersion": "7.0", "UILaunchImageOrientation": "Portrait",
    }],
}
with open(f"{app}/Info.plist", "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
with open(f"{app}/PkgInfo", "w") as f:
    f.write("APPL????")
