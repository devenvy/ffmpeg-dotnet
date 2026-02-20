# FFmpeg NuGet Build and Publish

This repository builds FFmpeg shared libraries and CLI binaries and packages them as `DevEnvy.FFmpeg.Binaries.LGPL`.

## What gets produced

- `runtimes/win-x64/native/*.dll`
- `runtimes/win-x64/native/ffmpeg.exe`
- `runtimes/win-x64/native/ffprobe.exe`
- `runtimes/linux-x64/native/libav*.so*`
- `runtimes/linux-x64/native/ffmpeg`
- `runtimes/linux-x64/native/ffprobe`
- `runtimes/linux-musl-x64/native/libav*.so*`
- `runtimes/linux-musl-x64/native/ffmpeg`
- `runtimes/linux-musl-x64/native/ffprobe`

## CI workflow

Use `.github/workflows/build-pack-publish.yml`.

- `workflow_dispatch`:
  - `ffmpeg_version`: FFmpeg source version (for example `7.1.3`)
  - `package_version`: NuGet package version
  - `publish`: publish to GitHub Packages (`true/false`)
- Tag push `v*`:
  - Uses package version from tag name (for example `v1.2.3` -> `1.2.3`)
  - Auto-publishes to GitHub Packages

## Required auth

Publishing uses the built-in `GITHUB_TOKEN` with `packages: write` permission.

## License posture

Build scripts intentionally use shared-library and non-GPL configure options:

- `--enable-shared`
- `--disable-static`
- `--disable-gpl`
- `--disable-nonfree`
