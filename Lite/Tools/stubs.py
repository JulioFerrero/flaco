"""Makes the SDK's library stubs usable for the iPhone 5c (armv7s).

Today's SDK stubs list only arm64e. The 5c's iOS 10 libraries have everything they declare and more, so a
copy with armv7s added to every target list links, plus the few symbols 32-bit ARM needs that arm64 never
did: struct returns in the Objective-C runtime, setjmp-style unwinding (used by @synchronized and __weak),
and the 64-bit arithmetic helpers, which on 32-bit iPhones live in libSystem rather than in a static library.

usage: python3 stubs.py <iPhoneOS.sdk> <out>
"""
import os
import re
import shutil
import sys

sdk, out = sys.argv[1:3]
EXTRA = {
    "/usr/lib/libobjc.A.dylib": "_objc_msgSend_stret, _objc_msgSendSuper_stret, _objc_msgSendSuper2_stret",
    "/usr/lib/system/libunwind.dylib": "__Unwind_SjLj_Register, __Unwind_SjLj_Unregister, __Unwind_SjLj_Resume, __Unwind_SjLj_RaiseException",
    "/usr/lib/system/libcompiler_rt.dylib": "___divdi3, ___udivdi3, ___moddi3, ___umoddi3, ___fixdfdi, ___fixsfdi, ___fixunsdfdi, "
                                            "___fixunssfdi, ___floatdidf, ___floatdisf, ___floatundidf, ___floatundisf",
}
TARGETS = re.compile(r"(targets:\s*\[)([^\]]*?)(\s*\])")

shutil.rmtree(out, ignore_errors=True)
for root, dirs, files in os.walk(sdk):
    for name in files:
        path = os.path.join(root, name)
        if not name.endswith(".tbd") or os.path.islink(path):
            continue
        text = open(path).read()
        text = TARGETS.sub(lambda m: m.group(1) + m.group(2) + ", armv7s-ios" + m.group(3), text)
        # A stub can hold several libraries, one YAML document each.
        documents = text.split("\n--- !tapi-tbd")
        for i, document in enumerate(documents):
            match = re.search(r"install-name:\s*'([^']+)'", document)
            if match and match.group(1) in EXTRA:
                block = f"  - targets:         [ armv7s-ios ]\n    symbols:         [ {EXTRA[match.group(1)]} ]\n"
                documents[i] = re.sub(r"\nexports:\n", "\nexports:\n" + block, document, count=1)
        target = os.path.join(out, os.path.relpath(path, sdk))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        open(target, "w").write("\n--- !tapi-tbd".join(documents))
# Symlinked stubs (libobjc.tbd → libobjc.A.tbd and the like), recreated inside the copy.
for root, dirs, files in os.walk(sdk):
    for name in files + dirs:
        path = os.path.join(root, name)
        if os.path.islink(path) and (name.endswith(".tbd") or os.path.isdir(path)):
            target = os.path.join(out, os.path.relpath(path, sdk))
            if not os.path.lexists(target) and os.path.isdir(os.path.dirname(target)):
                os.symlink(os.readlink(path), target)
