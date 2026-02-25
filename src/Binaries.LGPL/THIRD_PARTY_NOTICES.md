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

## Source and scripts

The build scripts and workflow used to produce these binaries are included in this repository under:

- `scripts/`
- `.github/workflows/`

When publishing, keep versioned source access available for the FFmpeg version shipped.
