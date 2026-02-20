# DevEnvy.FFmpeg.Binaries

`DevEnvy.FFmpeg.Binaries` ships LGPL-oriented FFmpeg shared libraries and CLI binaries (`ffmpeg`/`ffprobe`) for:

- `win-x64`
- `linux-x64` (glibc, Ubuntu-compatible)
- `linux-musl-x64` (musl, Alpine-compatible)

## Usage

Add the package to your .NET app:

```bash
dotnet add package DevEnvy.FFmpeg.Binaries
```

At runtime, .NET resolves the correct native assets from `runtimes/<rid>/native`.

## Important notes

- This package supports both dynamic-linking scenarios (for example FFmpeg.AutoGen) and CLI-driven scenarios (for example FFMpegCore).
- This package includes a dependency on a compatible `FFmpeg.AutoGen` version, so consumers get the matching binding package transitively.
- If you need strict LGPL-only distribution, keep FFmpeg configured with:
  - `--disable-gpl`
  - `--disable-nonfree`
  - `--enable-shared`
  - `--disable-static`
- Ensure you comply with LGPL obligations for redistribution, including source and notices.
