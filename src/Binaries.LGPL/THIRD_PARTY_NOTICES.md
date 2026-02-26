# Third-Party Notices

This package redistributes FFmpeg shared libraries.

- Project: FFmpeg
- Website: https://ffmpeg.org/
- License: LGPL v2.1 or later (for this build configuration)

## Build posture for this package

These binaries are built with the intent to remain LGPL-compatible:

- `--disable-gpl`
- `--disable-nonfree`
- `--enable-shared`
- `--disable-static`
- `--disable-autodetect`

## Hardware acceleration headers (compile-time only)

The following MIT-licensed header packages are used at **compile time only** to enable
hardware-accelerated codecs. No code from these projects is linked into the binaries;
the actual hardware drivers are loaded at runtime via dlopen / COM / system frameworks.

### nv-codec-headers
- Project: https://github.com/FFmpeg/nv-codec-headers
- License: MIT
- Purpose: Compile-time headers for NVIDIA NVENC / NVDEC / CUDA Video

### AMF (Advanced Media Framework)
- Project: https://github.com/GPUOpen-LibrariesAndSDKs/AMF
- License: MIT
- Purpose: Compile-time headers for AMD hardware encoding (Windows only)

## Hardware acceleration libraries (statically linked dispatcher)

The following MIT-licensed library is compiled as a **static archive** and linked into
the FFmpeg shared libraries. The dispatcher itself dynamically loads the actual GPU
runtime at execution time — no extra DLLs/SOs are bundled in this package.

### libvpl (Intel oneVPL)
- Project: https://github.com/intel/libvpl
- License: MIT
- Purpose: Intel Quick Sync Video (QSV) dispatcher for hardware encode/decode (Windows and Linux x64)
- Build: Static dispatcher linked into FFmpeg; at runtime it dynamically loads the Intel GPU driver
- Runtime: Requires Intel GPU driver with oneVPL/Media SDK runtime

## Source and scripts

The build scripts and workflow used to produce these binaries are included in this repository under:

- `scripts/`
- `.github/workflows/`

When publishing, keep versioned source access available for the FFmpeg version shipped.
