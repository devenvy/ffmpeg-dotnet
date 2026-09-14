#!/usr/bin/env python3
"""Audit an extracted upstream FFmpeg artifact for portability defects.

Emits one JSON object per artifact so a full matrix can be summarised. Parses
Mach-O / ELF / PE structures directly rather than grepping strings: ffmpeg
embeds its entire configure line in every binary, so a string search for build
paths reports a false positive on every single file.

Usage:  audit-upstream.py <extracted-dir> <artifact-name>
"""
import json
import re
import struct
import sys
from pathlib import Path

# ---------------------------------------------------------------- Mach-O ----
LC_ID_DYLIB, LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB = 0x0D, 0x0C, 0x18
LC_REEXPORT_DYLIB, LC_RPATH, LC_CODE_SIGNATURE = 0x8000001F, 0x8000001C, 0x1D
LC_BUILD_VERSION, LC_VERSION_MIN_MACOSX = 0x32, 0x24
APPLE_PLATFORM = {1: 'macOS', 2: 'iOS', 3: 'tvOS', 6: 'macCatalyst', 7: 'iOS-simulator'}
MACHO_MAGIC = (0xFEEDFACF, 0xCFFAEDFE, 0xFEEDFACE, 0xCEFAEDFE)
FAT_MAGIC = (0xCAFEBABE, 0xBEBAFECA)


def macho(data):
    if len(data) < 32:
        return None
    magic = struct.unpack_from('<I', data, 0)[0]
    if struct.unpack_from('>I', data, 0)[0] in FAT_MAGIC:
        return {'fat': True, 'id': None, 'load': [], 'rpath': [], 'signed': True}
    if magic not in MACHO_MAGIC:
        return None
    is64 = magic in (0xFEEDFACF, 0xCFFAEDFE)
    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32 if is64 else 28
    out = {'fat': False, 'id': None, 'load': [], 'rpath': [], 'signed': False, 'minos': None}
    for _ in range(min(ncmds, 4096)):
        if off + 8 > len(data):
            break
        cmd, size = struct.unpack_from('<II', data, off)
        if size == 0:
            break
        if cmd in (LC_ID_DYLIB, LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_RPATH):
            so = struct.unpack_from('<I', data, off + 8)[0]
            s = data[off + so:off + size].split(b'\0')[0].decode('utf-8', 'replace')
            if cmd == LC_ID_DYLIB:
                out['id'] = s
            elif cmd == LC_RPATH:
                out['rpath'].append(s)
            else:
                out['load'].append(s)
        elif cmd == LC_CODE_SIGNATURE:
            out['signed'] = True
        elif cmd == LC_BUILD_VERSION:
            plat, minos, _sdk = struct.unpack_from('<III', data, off + 8)
            out['minos'] = f"{APPLE_PLATFORM.get(plat, plat)} {minos >> 16}.{(minos >> 8) & 0xFF}"
        elif cmd == LC_VERSION_MIN_MACOSX:
            v = struct.unpack_from('<I', data, off + 8)[0]
            out['minos'] = f"macOS {v >> 16}.{(v >> 8) & 0xFF}"
        off += size
    return out


# ------------------------------------------------------------------- ELF ----
def elf(data):
    if data[:4] != b'\x7fELF':
        return None
    is64 = data[4] == 2
    try:
        shoff = struct.unpack_from('<Q' if is64 else '<I', data, 0x28 if is64 else 0x20)[0]
        shent, shnum, _ = struct.unpack_from('<HHH', data, 0x3A if is64 else 0x2E)
        secs = []
        for i in range(shnum):
            o = shoff + i * shent
            st = struct.unpack_from('<I', data, o + 4)[0]
            if is64:
                so, sz, ln = (struct.unpack_from('<Q', data, o + 24)[0],
                              struct.unpack_from('<Q', data, o + 32)[0],
                              struct.unpack_from('<I', data, o + 40)[0])
            else:
                so, sz, ln = (struct.unpack_from('<I', data, o + 16)[0],
                              struct.unpack_from('<I', data, o + 20)[0],
                              struct.unpack_from('<I', data, o + 24)[0])
            secs.append((st, so, sz, ln))
        dyn = next((s for s in secs if s[0] == 6), None)
        if not dyn:
            return {'needed': [], 'runpath': None, 'soname': None}
        strt = secs[dyn[3]]
        needed, runpath, soname = [], None, None
        step = 16 if is64 else 8
        for o in range(dyn[1], dyn[1] + dyn[2], step):
            tag, val = struct.unpack_from('<qQ' if is64 else '<iI', data, o)
            if tag == 0:
                break
            if tag in (1, 14, 15, 29):
                p = strt[1] + val
                s = data[p:data.index(b'\0', p)].decode('utf-8', 'replace')
                if tag == 1:
                    needed.append(s)
                elif tag == 14:
                    soname = s
                else:
                    runpath = s
        glibc = None
        vers = re.findall(rb'GLIBC_(\d+)\.(\d+)', data)
        if vers:
            glibc = max((int(a), int(b)) for a, b in vers)
        align = set()
        phoff = struct.unpack_from('<Q' if is64 else '<I', data, 0x20 if is64 else 0x1C)[0]
        phent, phnum = struct.unpack_from('<HH', data, 0x36 if is64 else 0x2A)
        for i in range(phnum):
            o = phoff + i * phent
            if struct.unpack_from('<I', data, o)[0] == 1:   # PT_LOAD
                align.add(struct.unpack_from('<Q' if is64 else '<I', data, o + (48 if is64 else 28))[0])
        return {'needed': needed, 'runpath': runpath, 'soname': soname,
                'glibc': glibc, 'align': sorted(align)}
    except Exception:
        return None


# -------------------------------------------------------------------- PE ----
SYSTEM_DLL = re.compile(
    r'^(api-ms-|ext-ms-|kernel32|kernelbase|user32|gdi32|gdiplus|advapi32|ole32|oleaut32|'
    r'shell32|shlwapi|ws2_32|winmm|bcrypt|ncrypt|crypt32|secur32|psapi|version|msvcrt|'
    r'ucrtbase|vcruntime|dbghelp|iphlpapi|mfplat|mfreadwrite|mfuuid|d3d9|d3d11|d3d12|'
    r'dxgi|dxva2|evr|opengl32|setupapi|imm32|comdlg32|normaliz|userenv|netapi32|powrprof|'
    r'avicap32|avrt|cfgmgr32|strmiids|uuid|winspool|combase|rpcrt4|ntdll|wldap32|dnsapi|'
    r'mswsock|schannel|sspicli|winhttp|wininet|comctl32|shcore|d2d1|dwrite|dcomp)', re.I)


def pe(data):
    try:
        if data[:2] != b'MZ':
            return None
        po = struct.unpack_from('<I', data, 0x3C)[0]
        if data[po:po + 4] != b'PE\0\0':
            return None
        nsec = struct.unpack_from('<H', data, po + 6)[0]
        opt = po + 24
        magic = struct.unpack_from('<H', data, opt)[0]
        dd = opt + (112 if magic == 0x20B else 96)
        imp_rva = struct.unpack_from('<I', data, dd + 8)[0]
        delay_rva = struct.unpack_from('<I', data, dd + 13 * 8)[0]
        secs = []
        so = opt + struct.unpack_from('<H', data, po + 20)[0]
        for i in range(nsec):
            o = so + i * 40
            vs, va, rs, rp = struct.unpack_from('<IIII', data, o + 8)
            secs.append((va, max(vs, rs), rp))

        def off(rva):
            for va, sz, rp in secs:
                if va <= rva < va + sz:
                    return rp + (rva - va)
            return None

        def names(rva, stride, name_field):
            out = []
            o = off(rva) if rva else None
            if o is None:
                return out
            while True:
                ent = data[o:o + stride]
                if len(ent) < stride or ent == b'\0' * stride:
                    break
                nr = struct.unpack_from('<I', ent, name_field)[0]
                no = off(nr)
                if no:
                    out.append(data[no:data.index(b'\0', no)].decode('ascii', 'replace'))
                o += stride
            return out

        return {'imports': names(imp_rva, 20, 12), 'delay': names(delay_rva, 32, 4)}
    except Exception:
        return None


# ----------------------------------------------------------------- audit ----
# Matches any build-tree path regardless of CI root (/Users, /home/runner,
# /work, /__w). Non-greedy before .build/ so the marker is not swallowed.
DATA_PATH = re.compile(rb'/[A-Za-z0-9_./+-]{0,60}?[.]build/[A-Za-z0-9_./+-]{0,110}')
PKG_PREFIX = re.compile(rb'(?:/usr/local/opt|/opt/homebrew|/usr/local/Cellar|/home/linuxbrew)[^\x00"\s]{0,80}')
FFMPEG_LIBS = ('libav', 'libsw', 'libpostproc', 'avcodec', 'avdevice', 'avfilter',
               'avformat', 'avutil', 'swresample', 'swscale', 'postproc')
SYSTEM_ELF = re.compile(
    r'^(lib(c|m|dl|rt|pthread|gcc_s|stdc\+\+|atomic|anl|resolv|util|nsl)\.so|ld-linux|ld-musl|'
    r'libc\+\+|libmvec\.so|libz\.so|libdl\.so|'
    # musl names its libc per-architecture; it is the platform libc, not a dependency
    r'libc\.musl-[a-z0-9_]+\.so|'
    # Android NDK system libraries, present on every device at the documented API level
    r'liblog\.so|libandroid\.so|libmediandk\.so|libOpenSLES\.so|libcamera2ndk\.so|'
    r'libvulkan\.so|libEGL\.so|libGLESv[0-9]\.so|libnativewindow\.so|libjnigraphics\.so)')


def audit(root: Path, name: str):
    f = {'artifact': name, 'files': 0, 'issues': []}

    def add(kind, detail, path=''):
        f['issues'].append({'kind': kind, 'detail': detail, 'file': path})

    entries = [p for p in root.rglob('*') if not p.is_dir() and 'legal' not in p.parts]
    real = [p for p in entries if not p.is_symlink()]
    links = [p for p in entries if p.is_symlink()]
    f['files'] = len(entries)
    f['real'] = len(real)
    f['symlinks'] = len(links)
    f['has_legal'] = (root / 'legal').is_dir() or any('legal' in p.parts for p in root.rglob('*'))

    # Byte-identical real files: upstream symlinks these on Linux, so any platform
    # that ships them as copies is inconsistent and inflates the download.
    by_size = {}
    for p in real:
        by_size.setdefault(p.stat().st_size, []).append(p)
    dup_bytes = 0
    for size, group in by_size.items():
        if len(group) > 1 and size > 1048576:   # ignore headers; only real libraries
            digests = {}
            for p in group:
                d = hash(p.read_bytes())
                digests.setdefault(d, []).append(p)
            for d, same in digests.items():
                if len(same) > 1:
                    dup_bytes += size * (len(same) - 1)
                    add('duplicate-real-files',
                        f"{len(same)} byte-identical copies of {size // 1048576}MB: "
                        f"{sorted(x.name for x in same)}")
    f['duplicated_mb'] = round(dup_bytes / 1048576, 1)

    for p in sorted(real):
        rel = str(p.relative_to(root))
        try:
            data = p.read_bytes()
        except OSError:
            continue

        m = macho(data)
        if m and not m['fat']:
            if m['id'] and not m['id'].startswith('@'):
                add('macho-absolute-id', m['id'], rel)
            deps = [d for d in m['load']
                    if not d.startswith('@') and not d.startswith(('/usr/lib/', '/System/'))]
            if deps:
                add('macho-absolute-dep', deps[:3], rel)
            if deps and not m['rpath']:
                add('macho-no-rpath', 'binary loads by absolute path and has no LC_RPATH', rel)
            pkg = sorted({x.decode() for x in PKG_PREFIX.findall(data)})
            if pkg:
                add('macho-package-manager-dep', pkg[:2], rel)
            if not m['signed'] and 'arm64' in name:
                add('macho-unsigned-arm64', 'unsigned; Apple Silicon refuses to run this', rel)

        # A .tar.gz records Unix modes, so a non-executable ffmpeg is upstream's,
        # not an artefact of repackaging.
        if p.name in ('ffmpeg', 'ffprobe') and not (p.stat().st_mode & 0o111):
            add('not-executable', f"mode {oct(p.stat().st_mode & 0o777)} in the tarball", rel)

        if m and not m['fat'] and m['minos']:
            f.setdefault('minos', {})[rel] = m['minos']

        e = elf(data)
        if e is not None:
            ext = [n for n in e['needed']
                   if not SYSTEM_ELF.match(n) and not n.startswith(FFMPEG_LIBS)]
            if ext:
                add('elf-external-dep', ext, rel)
            if p.name in ('ffmpeg', 'ffprobe') and not e['runpath']:
                add('elf-no-runpath', 'executable cannot find sibling libraries', rel)
            if p.name.startswith('lib') and not e['soname'] and '.so' in p.name:
                add('elf-no-soname', 'library has no SONAME', rel)
            if e.get('glibc'):
                f.setdefault('glibc', {})[rel] = '%d.%d' % e['glibc']
            # Android 15+ and Play require 16 KiB-aligned LOAD segments.
            if 'android' in name and e.get('align') and 0x4000 not in e['align']:
                add('android-page-align',
                    f"LOAD align {[hex(a) for a in e['align']]}, needs 0x4000", rel)

        w = pe(data)
        if w:
            ext = [d for d in w['imports']
                   if not SYSTEM_DLL.match(d) and not d.lower().startswith(FFMPEG_LIBS)]
            if ext:
                add('pe-non-system-import', ext, rel)

        # Runtime data paths compiled into dependencies (fontconfig, libxml catalogs)
        # point at the build tree and silently disable those features for consumers.
        for hit in {x.decode() for x in DATA_PATH.findall(data)}:
            if any(k in hit for k in ('/etc/fonts', '/etc/xml', '/share/', '/etc/ssl')):
                add('baked-data-path', hit[:100], rel)
                break

    return f


if __name__ == '__main__':
    print(json.dumps(audit(Path(sys.argv[1]), sys.argv[2])))
