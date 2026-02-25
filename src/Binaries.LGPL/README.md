# DevEnvy.FFmpeg.Binaries.LGPL

`DevEnvy.FFmpeg.Binaries.LGPL` ships LGPL-oriented FFmpeg shared libraries and CLI binaries (`ffmpeg`/`ffprobe`) for:

- `win-x64`
- `linux-x64` (glibc, Ubuntu-compatible)
- `linux-musl-x64` (musl, Alpine-compatible)
- `osx-x64`
- `osx-arm64`

## Hardware Acceleration

All hardware acceleration is enabled via **compile-time headers only** (MIT-licensed) with runtime driver loading — fully LGPL-compatible:

| Platform | Accelerators |
|----------|-------------|
| Windows  | NVENC, NVDEC, CUDA, D3D11VA, DXVA2, AMF, MediaFoundation |
| Linux (glibc) | NVENC, NVDEC, CUDA, VAAPI, VDPAU, QSV (libvpl), V4L2 M2M |
| Linux (musl)  | NVENC, NVDEC, CUDA |
| macOS    | VideoToolbox, AudioToolbox |

> **Note:** QSV on Windows, RKMPP, and V4L2 on ARM hardware require additional build
> infrastructure not yet included. See the repository issues for roadmap.

## Usage

Add the package to your .NET app:

```bash
dotnet add package DevEnvy.FFmpeg.Binaries.LGPL
```

At runtime, native libraries are resolved from `ffmpeg/<rid>/` relative to the application base directory.

## Important notes

- This package supports both dynamic-linking scenarios (e.g. FFmpeg.AutoGen) and CLI-driven scenarios (e.g. FFMpegCore).
- This package includes a dependency on a compatible `FFmpeg.AutoGen` version, so consumers get the matching binding package transitively.
- If you need strict LGPL-only distribution, keep FFmpeg configured with:
  - `--disable-gpl`
  - `--disable-nonfree`
  - `--enable-shared`
  - `--disable-static`
  - `--disable-autodetect`
- Ensure you comply with LGPL obligations for redistribution, including source and notices.
