# FFmpeg binaries for .NET

Prebuilt FFmpeg native binaries from [`devenvy/ffmpeg`](https://github.com/devenvy/ffmpeg),
repackaged for .NET. This repository does **not** build FFmpeg — it downloads the upstream
release assets, verifies them against the release's `SHA256SUMS`, and packs them.

## Which package

Pick a license variant, then reference the platform you build for.

| License variant | FFmpeg build |
|---|---|
| `LGPLv2` | LGPL-2.1 — App-Store safe, no Vulkan |
| `LGPLv3` | LGPL-3.0 |
| `GPLv2`  | GPL-2.0 |
| `GPLv3`  | GPL-3.0 |

```
DevEnvy.FFmpeg.Binaries                        path helper, no binaries
DevEnvy.FFmpeg.Binaries.<variant>.Runtime.<rid>  one platform's binaries
DevEnvy.FFmpeg.Binaries.<variant>.Runtime.All    every platform
```

### The recommended pattern

Put this in your csproj and it works whether or not the build names a platform:

```xml
<ItemGroup Condition="'$(RuntimeIdentifier)' == ''">
  <PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.All" Version="9.0.1.700" />
</ItemGroup>
<ItemGroup Condition="'$(RuntimeIdentifier)' != ''">
  <PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.$(RuntimeIdentifier)" Version="9.0.1.700" />
</ItemGroup>
```

`$(RuntimeIdentifier)` is interpolated straight into the package id, so one pair of
conditions covers every platform — there is no per-RID block to maintain.

| What you run | What restores |
|---|---|
| `dotnet publish -r linux-x64` | `Runtime.linux-x64` only, ~32 MB |
| `dotnet build -r win-x64` | `Runtime.win-x64` only |
| `dotnet build` (no RID) | `Runtime.All`, ~415 MB, every platform |

If you only ever ship one platform, skip the conditions and reference
`...Runtime.linux-x64` directly.

### Two things that will bite

**Use `-p:RuntimeIdentifier=` for a standalone `restore`.** A bare `-r` on
`dotnet restore` populates NuGet's RID graph but leaves `$(RuntimeIdentifier)` empty
while the project is evaluated, so the first condition wins and you silently restore
every platform:

```bash
dotnet restore -r osx-arm64                     # wrong: resolves Runtime.All
dotnet restore -p:RuntimeIdentifier=osx-arm64   # correct
```

`dotnet build -r` and `dotnet publish -r` are fine — they set the property.

**An unsupported RID fails on a package name you never typed**, because the id is
built from `$(RuntimeIdentifier)`:

```
NU1101: Unable to find package DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.linux-musl-arm
```

To get a clearer error, validate first:

```xml
<PropertyGroup>
  <FFmpegSupportedRids>win-x64;win-arm64;linux-x64;linux-arm64;linux-arm;linux-musl-x64;linux-musl-arm64;osx-x64;osx-arm64;android-arm64;android-x64;ios-arm64;iossimulator-arm64;maccatalyst-arm64;maccatalyst-x64</FFmpegSupportedRids>
</PropertyGroup>
<Target Name="ValidateFFmpegRid" BeforeTargets="CollectPackageReferences"
        Condition="'$(RuntimeIdentifier)' != '' AND !$([System.String]::Copy(';$(FFmpegSupportedRids);').Contains(';$(RuntimeIdentifier);'))">
  <Error Text="FFmpeg binaries are not published for '$(RuntimeIdentifier)'. Supported: $(FFmpegSupportedRids)." />
</Target>
```

### Trimming a RID-less build

`Runtime.All` copies every platform into `bin/`. To narrow the copy without giving up
the RID-less build:

```xml
<PropertyGroup>
  <FFmpegRuntimeIdentifiers>linux-x64;win-x64</FFmpegRuntimeIdentifiers>
</PropertyGroup>
```

This trims build **and** publish output. It does not trim the restore — the packages
are still downloaded. Only naming a platform avoids the download.

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
| `ios-arm64`, `iossimulator-arm64` | one slice each, split from upstream's xcframework |
| `maccatalyst-arm64`, `maccatalyst-x64` | one universal slice, shipped whole to both |

Apple platforms consume native code through `@(NativeReference)` rather than
`runtimes/{rid}/native`, so those packages ship `.framework` bundles. Upstream publishes one
`.xcframework` holding every slice — right for Xcode, where one bundle serves every
destination — and this repo splits it so each RID's package carries only its own slice.

Mac Catalyst is a separate RID family in .NET — it resolves through `ios`, never `osx` — so
the macOS builds do not cover it. Upstream ships it as one universal `arm64 + x86_64` slice,
which both Catalyst packages carry whole, as Apple distributes Catalyst frameworks.

Not supported, because upstream does not build them: 32-bit `android-arm`, `browser-wasm`,
`tvos-*`, and the x86_64 iOS simulator.

## Versioning

Package versions are `{ffmpeg}.{z}` where `z = (upstream_build × 100) + our_build`.

```
upstream 9.0.1.5, our build 0  ->  9.0.1.700
upstream 9.0.1.7, our build 1  ->  9.0.1.701   (packaging fix, no upstream change)
upstream 9.0.1.8, our build 0  ->  9.0.1.800
```

Upstream's fourth component is a global counter shared across series — `8.1.2.5` and `9.0.1.5`
ship together — so per series it has gaps. Giving each counter its own digit range keeps them
from drifting into each other and makes the mapping reversible.

Several FFmpeg series are tracked at once from `versions.json`, and each releases
independently — an 8.1 upstream release ships as soon as it appears, whether or not 9.0 has
moved. Neither series waits for the other and their version lines never collide:

```
8.1.2.700 < 8.1.2.800 < 9.0.1.700 < 9.0.1.501 < 9.0.1.600
```

### Staying on a series

Because 9.0's versions sort above 8.1's, a floating reference always lands on the newest
series. To track 8.1 and keep receiving its updates, use a range:

```xml
<PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.linux-x64" Version="8.1.*" />
```

A floating `8.1.*` resolves to the newest 8.1 release and never crosses to 9.0.

Do **not** use a range like `[8.1,9.0)` for this: `PackageReference` resolves the
*lowest* version a range allows, so it would pin you to the first 8.1 release and never
move. Use an exact version (`[8.1.2.700]`) only when you want no movement at all.

## Migrating from `DevEnvy.FFmpeg.Binaries.LGPL`

That package is unlisted. Its successor is `DevEnvy.FFmpeg.Binaries.LGPLv2` (upstream's `lgplv2`
variant is the same LGPL-2.1 build it always shipped). Two changes to expect:

- Binaries moved from `ffmpeg/{rid}/` to NuGet's standard `runtimes/{rid}/native/`. Code calling
  `FFmpegBinaries.GetLibraryPath()` is unaffected; code hard-coding the old path is not.
- One package per platform instead of one fat package, so a reference now names a platform
  (or `Runtime.All`). See the pattern above.
- `FFmpegBinaries` now lives in `DevEnvy.FFmpeg.Binaries`, which the platform packages depend on.

## Building locally

```bash
RIDS="linux-x64" CELLS="lgplv2" PACK_IOS=0 \
  ./scripts/pack.sh 9.0.1.5 0.0.0-local --output ./nupkgs --phase base
./scripts/verify-packages.sh ./nupkgs
./scripts/verify-consumer.sh ./nupkgs 0.0.0-local
```

Run it on Linux or WSL. On Windows `tar` cannot create symlinks, so the duplicate-library
problem the staging normalization exists to prevent does not reproduce there.
