# Building FFmpeg for `DevEnvy.FFmpeg.Binaries.LGPL`

## Intent

Build FFmpeg as shared libraries per target runtime identifier (RID), then place outputs in:

- `runtimes/win-x64/native`
- `runtimes/linux-x64/native`
- `runtimes/linux-musl-x64/native`

This allows .NET runtime-native resolution when apps reference the NuGet package.

## Can Windows be built on Linux?

Yes, with cross-compilers (for example MinGW).  
In practice, this repository builds `win-x64` on `windows-latest` using MSYS2 for better reliability and fewer toolchain edge cases.

## Why separate Ubuntu and Alpine builds?

Ubuntu uses glibc and Alpine uses musl; native binaries are not ABI-compatible across those libc families.

## Local script entry points

- `scripts/build-ffmpeg-linux-gnu.sh`
- `scripts/build-ffmpeg-linux-musl.sh`
- `scripts/build-ffmpeg-msys2.sh`
