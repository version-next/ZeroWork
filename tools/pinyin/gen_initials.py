"""Generate the static pinyin-initials table for CJK Unified Ideographs (U+4E00..U+9FFF).

Uses only the macOS system CoreFoundation CFStringTransform (kCFStringTransformMandarinLatin,
then kCFStringTransformStripDiacritics); nothing is downloaded. One output byte per code point:
the lowercase ASCII initial of the character's default Mandarin reading, or '-' if none.
Usage: python3 -I gen_initials.py <output-file>
"""
import ctypes, ctypes.util, sys

cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))
CFIndex = ctypes.c_long
cf.CFStringCreateMutable.restype = ctypes.c_void_p
cf.CFStringCreateMutable.argtypes = [ctypes.c_void_p, CFIndex]
cf.CFStringAppendCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
cf.CFStringTransform.restype = ctypes.c_bool
cf.CFStringTransform.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_bool]
cf.CFStringGetCString.restype = ctypes.c_bool
cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, CFIndex, ctypes.c_uint32]
cf.CFRelease.argtypes = [ctypes.c_void_p]
UTF8 = 0x08000100
mandarin = ctypes.c_void_p.in_dll(cf, "kCFStringTransformMandarinLatin")
strip = ctypes.c_void_p.in_dll(cf, "kCFStringTransformStripDiacritics")

def initial(cp):
    s = cf.CFStringCreateMutable(None, 0)
    cf.CFStringAppendCString(s, chr(cp).encode("utf-8"), UTF8)
    cf.CFStringTransform(s, None, mandarin, False)
    cf.CFStringTransform(s, None, strip, False)
    buf = ctypes.create_string_buffer(64)
    cf.CFStringGetCString(s, buf, 64, UTF8)
    cf.CFRelease(s)
    text = buf.value.decode("utf-8", "replace").strip().lower()
    c = text[:1]
    return c if "a" <= c <= "z" else "-"

out = "".join(initial(cp) for cp in range(0x4E00, 0xA000))
assert len(out) == 0xA000 - 0x4E00
with open(sys.argv[1], "w", encoding="ascii") as f:
    f.write(out)
print("chars", len(out), "unmapped", out.count("-"))
