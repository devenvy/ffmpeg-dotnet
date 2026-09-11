# FFmpeg binaries for .NET

Prebuilt FFmpeg native binaries from [`devenvy/ffmpeg`](https://github.com/devenvy/ffmpeg),
repackaged for .NET. This repository does **not** build FFmpeg — it downloads the upstream
release assets, verifies them against the release's `SHA256SUMS`, and packs them.

## Which package

Pick a license cell, then pick how much you want restored.

| License cell | FFmpeg build |
|---|---|
| `LGPLv2` | LGPL-2.1 — App-Store safe, no Vulkan |
| `LGPLv3` | LGPL-3.0 |
| `GPLv2`  | GPL-2.0 |
| `GPLv3`  | GPL-3.0 |

```
DevEnvy.FFmpeg.Binaries.<cell>           every platform, works without a RID
DevEnvy.FFmpeg.Binaries.<cell>.Rid       only the platform you build for
DevEnvy.FFmpeg.Binaries.<cell>.Runtime.<rid>   one platform, referenced directly
DevEnvy.FFmpeg.Binaries.<cell>.Apple     iOS xcframeworks
DevEnvy.FFmpeg.Binaries                  path helper, no binaries
```

### `.Rid` — recommended when you build for a known platform

```xml
<PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Rid" Version="9.0.1.500" />
```

Resolves native binaries **per RuntimeIdentifier**, so `dotnet publish -r linux-x64` downloads
one platform (~32 MB) instead of twelve (~415 MB). It works with a single `RuntimeIdentifier`
and with a project-declared `RuntimeIdentifiers` list, which is the shape .NET Android uses for
multi-ABI builds, so MAUI heads are served without extra configuration.

A build that sets **neither** resolves no binaries at all and warns `DEVFFM001`. That is the
tradeoff for the precise restore — use the plain package instead if you need a RID-less build.

### The plain package — when you need a portable build

```xml
<PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2" Version="9.0.1.500" />
```

Carries every platform, so `dotnet build` with no RID works and an app really can run anywhere.
That costs ~415 MB restored and every platform copied into `bin/`. To narrow the copy without
giving up the RID-less build:

```xml
<PropertyGroup>
  <FFmpegRuntimeIdentifiers>linux-x64;win-x64</FFmpegRuntimeIdentifiers>
</PropertyGroup>
```

This trims build **and** publish output. It does not trim the restore — the packages are still
downloaded. Only `.Rid` or a direct `Runtime.<rid>` reference avoids the download.

iOS is deliberately not a dependency of the plain package: an iOS head always builds with a
RID, so it is served by `.Rid`, and this keeps 36 MB of xcframeworks out of every server app.

## Using it

```csharp
using DevEnvy.FFmpeg.Binaries;

string dir = FFmpegBinaries.GetLibraryPath();
```

`GetLibraryPath()` handles both layouts the SDK produces: a RID-agnostic build nests binaries
under `runtimes/{rid}/native/`, while a RID-specific build or publish flattens them into the
output root.

This package brings **no binding library**. Pair it with FFmpeg.AutoGen:

```csharp
DynamicallyLoadedBindings.LibrariesPath = FFmpegBinaries.GetLibraryPath();
DynamicallyLoadedBindings.Initialize();
```

`GetFFmpegPath()` and `GetFFprobePath()` return the CLI tools, or `null` on Android and iOS —
upstream builds those platforms to be linked into an app, not shelled out to.

## Platforms

| RID | Notes |
|---|---|
| `win-x64`, `win-arm64` | |
| `linux-x64`, `linux-arm64`, `linux-arm` | `linux-arm` is upstream's `armhf` |
| `linux-musl-x64`, `linux-musl-arm64` | Alpine |
| `osx-x64`, `osx-arm64` | |
| `android-arm64`, `android-x64` | libraries only; `x64` is the emulator |
| `ios-arm64`, `iossimulator-arm64` | via the `.Apple` package |

Not supported, because upstream does not build them: `maccatalyst-*`, 32-bit `android-arm`,
`browser-wasm`, `tvos-*`, and the x86_64 iOS simulator. Mac Catalyst is a separate RID family
in .NET — it resolves through `ios`, never `osx` — so the macOS builds do not cover it.

## Versioning

Package versions are `{ffmpeg}.{z}` where `z = (upstream_build × 100) + our_build`.

```
upstream 9.0.1.5, our build 0  ->  9.0.1.500
upstream 9.0.1.5, our build 1  ->  9.0.1.501   (packaging fix, no upstream change)
upstream 9.0.1.6, our build 0  ->  9.0.1.600
```

Upstream's fourth component is a global counter shared across series — `8.1.2.5` and `9.0.1.5`
ship together — so per series it has gaps. Giving each counter its own digit range keeps them
from drifting into each other and makes the mapping reversible.

Several FFmpeg series are tracked at once from `versions.json`; each releases independently.

## Migrating from `DevEnvy.FFmpeg.Binaries.LGPL`

That package is unlisted. Its successor is `DevEnvy.FFmpeg.Binaries.LGPLv2` (upstream's `lgplv2`
cell is the same LGPL-2.1 build it always shipped). Two changes to expect:

- Binaries moved from `ffmpeg/{rid}/` to NuGet's standard `runtimes/{rid}/native/`. Code calling
  `FFmpegBinaries.GetLibraryPath()` is unaffected; code hard-coding the old path is not.
- `FFmpegBinaries` now lives in `DevEnvy.FFmpeg.Binaries`, which the cell packages depend on.

## Building locally

```bash
RIDS="linux-x64" CELLS="lgplv2" PACK_IOS=0 \
  ./scripts/pack.sh 9.0.1.5 0.0.0-local --output ./nupkgs --phase base
./scripts/verify-packages.sh ./nupkgs
./scripts/verify-consumer.sh ./nupkgs 0.0.0-local
```

Run it on Linux or WSL. On Windows `tar` cannot create symlinks, so the duplicate-library
problem the staging normalization exists to prevent does not reproduce there.
