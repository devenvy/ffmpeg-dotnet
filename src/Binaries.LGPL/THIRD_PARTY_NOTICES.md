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

## Source and scripts

The build scripts and workflow used to produce these binaries are included in this repository under:

- `scripts/`
- `.github/workflows/`

When publishing, keep versioned source access available for the FFmpeg version shipped.
