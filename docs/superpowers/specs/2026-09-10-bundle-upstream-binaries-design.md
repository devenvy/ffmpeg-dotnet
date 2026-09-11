# Bundle upstream FFmpeg binaries

**Status:** implemented — see "Revisions during implementation" below
**Date:** 2026-09-10
**Verified against:** `devenvy/ffmpeg` releases `9.0.1.5` and `8.1.2.5` (both 2026-09-10)

## Revisions during implementation

The sections below describe the approved design. Eight things changed while building it, each
because something was measured or reviewed rather than assumed. Where a section further down
contradicts this list, this list is current.

1. **Added a second meta per cell, `…{Cell}.Rid`, carrying `runtime.json`.** The original design
   trimmed only what reached `bin/`; the restore still pulled every platform. Measured against
   real assets that is **415 MB for one cell**. `runtime.json` is NuGet's RID-conditional
   dependency mechanism and cuts it to one platform (~32 MB). Verified: it fires for
   `$(RuntimeIdentifier)` and for a project-declared `$(RuntimeIdentifiers)` list — the shape
   .NET Android uses — and unlike a conditional `PackageReference` it is immune to the
   difference between `-r` and `-p:RuntimeIdentifier=`. A RID-less build resolves nothing from
   it, which is why the all-platform meta remains.
2. **Per-TFM dependency groups dropped.** They existed to keep iOS assets out of server apps.
   `runtime.json` handles platform selection by RID instead, so the groups — and the NU1012
   platform-version tax they carry — are unnecessary. The all-platform meta simply does not
   depend on the Apple package; an iOS head always has a RID and is served by `.Rid`.
3. **The helper no longer depends on `FFmpeg.AutoGen`.** Codex review: AutoGen's dynamically
   loaded resolver builds versioned Unix names (`libavcodec.so.61`) and cannot load Android's
   unversioned `.so` files or iOS frameworks, so depending on it would advertise mobile bindings
   that do not work. The helper is now pure path resolution; consumers add a binding themselves.
4. **`legal/` is packed at the package root, never under `runtimes/**/native/`.** Anything below
   `native/` is a native asset NuGet copies into every consumer's build and publish output.
5. **`release.yml` is not tag-triggered.** The original design had it triggered by a tag *and*
   creating that tag, which cannot work. It now runs on a merge to `main` or by hand, and is
   idempotent: a series is released when its computed version has no `v*` tag yet.
6. **`our_build` is bounded to 0–99 and fails loudly at 100.** The two counters share one integer
   only while ours stays in its own range; at 100 it would carry into upstream's digits and claim
   a build that does not exist.
7. **`ffmpeg`/`ffprobe` get `chmod +x` from the runtime package's targets.** A `.nupkg` is a zip
   and NuGet does not carry Unix permissions — the currently published package ships them mode
   `0644`, so `Process.Start` fails with `EACCES` on Linux and macOS. Verified that `exec` needs
   the bit and `read` does not, so shared libraries were never affected.
8. **Package count is 57, not 53** — the four `.Rid` metas, plus the helper, 4 metas, 44 runtime
   and 4 Apple packages.

One review finding was investigated and **not** acted on. Codex flagged that `linux-musl-x64`
falls back to `linux-x64` in the RID graph, so the all-platform meta can have NuGet select glibc
assets from one package and musl assets from another under identical filenames. The RID-graph
claim is correct and `project.assets.json` confirms both are selected. Empirically the SDK's
conflict resolution then picks musl, deterministically and independently of `PackageReference`
order, so the built output is right. It is recorded here as a known smell — correctness rests on
conflict resolution rather than on not creating the conflict — and `.Rid` avoids it entirely by
resolving exactly one package.

## Overview

This repository currently builds FFmpeg from source across six cross-compilation jobs and
packs the results into one fat NuGet package. It will instead download prebuilt release
assets from [`devenvy/ffmpeg`](https://github.com/devenvy/ffmpeg) and repackage them, with
no compilation of its own.

### Goals

- Stop building FFmpeg. CI drops from hours of cross-compilation to minutes of download-and-pack.
- Ship every upstream platform and every license cell.
- Let a consumer pull only the platforms they ship, rather than all of them.
- Open a PR automatically when an upstream release appears, for every tracked series.

### Non-goals

- Changing upstream artifacts. Everything upstream does deliberately (bundled mobile headers,
  `libc++_shared.so`, xcframeworks, Unix symlink triples, NDK ABI directory names) is adapted
  here, not upstream.

  The platform gaps that *were* worth raising — `android-x64`, `linux-musl-arm64`, `win-arm64`,
  the iOS Vulkan discrepancy, and an aggregate checksum manifest — were each argued on grounds
  that hold for any consumer of these artifacts, and all landed upstream in `9.0.1.5` /
  `8.1.2.5` (devenvy/ffmpeg PRs #13–#16). This design targets that artifact set.
- Supporting platforms upstream does not ship: `maccatalyst-*`, `android-arm` (32-bit),
  `browser-wasm`, `tvos-*`, `iossimulator-x64`.

## Upstream artifact inventory

Each release publishes 85 assets: 84 tarballs (21 platform-artifacts x 4 license cells) plus
an aggregate `SHA256SUMS`. Cells are `lgplv2`, `lgplv3`, `gplv2`, `gplv3`. Desktop platforms
additionally publish a `-dev` tarball (headers + Windows import libraries) which this repo
never downloads.

| Upstream artifact | .NET RID | Shape |
|---|---|---|
| `win-x64` | `win-x64` | flat `*.dll` + `ffmpeg.exe`, `ffprobe.exe` |
| `win-arm64` | `win-arm64` | same |
| `linux-x64` | `linux-x64` | `*.so` symlink triples + `ffmpeg`, `ffprobe` |
| `linux-arm64` | `linux-arm64` | same |
| `linux-armhf` | `linux-arm` | same — note the RID rename |
| `linux-musl-x64` | `linux-musl-x64` | same |
| `linux-musl-arm64` | `linux-musl-arm64` | same |
| `osx-x64` | `osx-x64` | `*.dylib` triples + `ffmpeg`, `ffprobe` |
| `osx-arm64` | `osx-arm64` | same |
| `android-arm64` | `android-arm64` | `include/` + `lib/arm64-v8a/*.so` + `libc++_shared.so` |
| `android-x64` | `android-x64` | `include/` + `lib/x86_64/*.so` + `libc++_shared.so` |
| `ios` | `ios-arm64`, `iossimulator-arm64` | six `.xcframework` bundles |

All twelve carry a `legal/` directory holding the cell's license notice plus every bundled
dependency's license. It is shipped in every package — it is the LGPL compliance payload.

Since upstream release `9.0.1.5`, MoltenVK is statically linked into the iOS libraries, so
every iOS cell now contains exactly the same six xcframeworks. The staging code still
enumerates them rather than assuming six, so a future seventh does not silently vanish.

## Package topology

**53 packages per release.**

```
DevEnvy.FFmpeg.Binaries                         helper assembly + FFmpeg.AutoGen dependency
DevEnvy.FFmpeg.Binaries.{Cell}                  4 metas: LGPLv2, LGPLv3, GPLv2, GPLv3
DevEnvy.FFmpeg.Binaries.{Cell}.Runtime.{rid}    44 = 11 RIDs x 4 cells
DevEnvy.FFmpeg.Binaries.{Cell}.Apple            4  = iOS xcframeworks, 1 per cell
```

`DevEnvy.FFmpeg.Binaries.LGPL` (published through `8.0.1.4`) is **unlisted** on nuget.org
rather than aliased. The README documents `DevEnvy.FFmpeg.Binaries.LGPLv2` as its successor.
Unlisting leaves existing pinned references resolvable while removing the ID from search.

### Why a meta package needs per-TFM dependency groups

A meta that depended on all twelve platform packages for every target framework would drag
iOS xcframeworks into a Linux server app. NuGet resolves dependencies per target framework,
so each meta multi-targets and declares different dependencies per group:

| Meta TFM | Depends on |
|---|---|
| `netstandard2.0` | the 9 desktop/server runtime packages |
| `net10.0-android` | `Runtime.android-arm64`, `Runtime.android-x64` |
| `net10.0-ios` | `.Apple` |

`netstandard2.0` is the fallback group, so a `net8.0` or `net10.0` console app gets exactly
the desktop set and nothing mobile.

## Project layout

Four parameterized csproj files produce all 53 packages. `scripts/pack.sh` invokes them in a
loop with `-p:Cell=` and `-p:Rid=`.

```
src/DevEnvy.FFmpeg.Binaries/          netstandard2.0 helper assembly
src/DevEnvy.FFmpeg.Binaries.Meta/     packed 4x   (-p:Cell=)
src/DevEnvy.FFmpeg.Binaries.Runtime/  packed 44x  (-p:Cell= -p:Rid=)
src/DevEnvy.FFmpeg.Binaries.Apple/    packed 4x   (-p:Cell=)
```

Fifty-three hand-maintained csproj files would guarantee drift between them. This mirrors the
approach `ffmpeg-dotnet` uses for its 28 packages.

## Staging normalization

`scripts/pack.sh` runs a per-platform normalization over each extracted tarball before packing.
The rules differ because the four artifact shapes genuinely differ.

### Windows — no action

Flat DLLs with no links. Nothing to do.

### Linux and macOS — collapse the symlink triple

Upstream ships three names per library, two of them symlinks:

```
libavcodec.so              -> libavcodec.so.63.1.101    link-time only
libavcodec.so.63           -> libavcodec.so.63.1.101    SONAME, the loaded name
libavcodec.so.63.1.101                                  real file
```

**A `.nupkg` is a zip written by NuGet, and NuGet has no symlink representation** — a link left
in staging is packed as a full byte copy of its target. Packed verbatim, every runtime package
carries three copies of every library.

Staging keeps one real file under the **SONAME** (`libavcodec.so.63` on Linux,
`libavcodec.63.dylib` on macOS) and drops the other two. That name is not a guess: the `ffmpeg`
binary's `DT_NEEDED` entries name it, and FFmpeg.AutoGen's dynamic loader builds `lib{0}.so.{1}`
on Linux and `lib{0}.{1}.dylib` on macOS.

**The tradeoff this accepts:** .NET's default P/Invoke probing tries `avcodec`, `libavcodec`,
`avcodec.so`, `libavcodec.so` and never appends a version suffix, so a consumer writing
`[DllImport("avcodec")]` against the unversioned name gets `DllNotFoundException`. Nothing this
repo ships uses that path, and the README documents the `SetDllImportResolver` workaround. Do
not "fix" it by restoring the unversioned name — it costs a full extra copy of every library.

A dangling link is left alone so packing fails loudly rather than silently shipping a package
with a library missing.

### Android — drop headers, flatten the ABI directory

1. **Delete `include/`** (153 files). Upstream bundles headers in mobile tarballs deliberately,
   because "those builds exist only to be linked" — correct for Gradle consumers, wrong here.
   It is also actively harmful: a RID-specific .NET publish flattens everything under `native/`
   into the publish root, so the per-library `version.h` files collide and the build fails with
   **NETSDK1152**.
2. **Flatten `lib/{arm64-v8a,x86_64}/` into the staging root**, which becomes
   `runtimes/android-{arm64,x64}/native/`. The NDK ABI names are correct for `jniLibs`; the RID
   names are correct for NuGet.
3. **Keep `libc++_shared.so`.** `libavcodec` and `libavfilter` are built from C++ and linked
   against `c++_shared`; the app crashes on load without it. The README documents the
   duplicate-soname case for consumers whose app already carries one.

Android libraries have unversioned sonames, so the symlink collapse does not apply.

### iOS — no normalization

The six xcframeworks are copied whole. They are the idiomatic Apple distribution format, and
their slices are deliberately dynamic rather than static so the App-Store `lgplv2` cell
satisfies LGPLv2.1 section 6's relink requirement.

## Package layouts

### Runtime packages — `runtimes/{rid}/native/`

The standard NuGet native layout, which gets RID resolution for free. Verified behavior:

| Consumer build | Result |
|---|---|
| `dotnet build -r linux-x64` | only linux-x64, **flattened into the output root** |
| `dotnet publish -r linux-x64` | only linux-x64, flattened into the publish root |
| `dotnet build` (no RID) | **every** RID, nested under `runtimes/{rid}/native/` |

The third row is why consumer trimming exists.

### Apple package — `@(NativeReference)`

RID-native probing does not apply on iOS. The package ships the xcframeworks and a
`buildTransitive/net10.0-ios/` targets file that adds each one:

```xml
<NativeReference Include="$(MSBuildThisFileDirectory)../../frameworks/libavcodec.xcframework"
                 Kind="Framework" />
```

Xcode selects the device or simulator slice and strips the unused one from the shipped app.

## Consumer trimming

A RID-agnostic build copies every platform. Consumers who care set:

```xml
<PropertyGroup>
  <FFmpegRuntimeIdentifiers>linux-x64;win-x64</FFmpegRuntimeIdentifiers>
</PropertyGroup>
```

The metas' `buildTransitive` targets then filter the copy. Three implementation details, each
established by testing rather than assumption:

1. **Build and publish resolve separately.** Filtering `ReferenceCopyLocalPaths` trims the build
   output but has no effect on publish, which computes `ResolvedFileToPublish` on its own path.
   Both need a filter, on `ComputeResolvedFilesToPublishList` for the latter.
2. **The filter must be scoped by `NuGetPackageId`.** These targets ship in a package that sits
   in someone else's project; unscoped, they would trim that project's *other* native packages.
3. **The filter must be skipped when `RuntimeIdentifier` is set**, because the SDK has already
   selected a single RID and flattened it — the `RuntimeIdentifier` metadata the filter keys on
   is no longer present in the same shape.

**Limit worth documenting:** this trims what lands in `bin`/`publish`. The runtime packages are
still restored to the global packages folder. A consumer who wants to avoid the download
references `DevEnvy.FFmpeg.Binaries.{Cell}.Runtime.{rid}` directly and skips the meta.

## Helper package

`FFmpegBinaries` moves from the variant package into its own `DevEnvy.FFmpeg.Binaries`, so one
copy serves all four cells and switching cells does not swap assemblies. It keeps the
`FFmpeg.AutoGen.Bindings.DynamicallyLoaded` dependency, resolved at release time to the newest
version matching the FFmpeg series (`8.1` -> `8.1.0`, `9.0` -> `9.0.1.1`; both exist today).

Three changes to the current implementation:

1. **`GetLibraryPath()` must probe two layouts.** RID-agnostic builds nest under
   `runtimes/{rid}/native/`; RID-specific publish flattens into the base directory. Probe the
   nested path, fall back to `AppContext.BaseDirectory`.
2. **Replace the `ldd --version` subprocess** used for musl detection with
   `RuntimeInformation.RuntimeIdentifier`, which reports `linux-musl-*` directly. The current
   code spawns a process on every call and swallows all exceptions.
3. **`win-arm64` becomes real.** The current code returns a `win-arm64` path for ARM Windows
   despite no such binaries ever having existed — a latent `DirectoryNotFoundException`.
   Upstream now ships it.

`GetFFmpegPath()` and `GetFFprobePath()` keep their signatures but must return `null` (or throw
a documented exception) on Android and iOS, which ship libraries only and no executables.

## Versioning

Upstream's fourth component is a **global build counter** shared across series, not a per-version
one: `8.1.2.5` and `9.0.1.5` were published at the same instant. Per series it therefore has
gaps — `9.0.1` went `.0, .1, .2, .4, .5` with no `.3`.

Package version is:

```
w.x.y.z   where   z = (upstream_z * 100) + our_build
```

`w.x.y` is the FFmpeg version, `upstream_z` is upstream's build counter, and `our_build` is this
repo's counter for packaging-only changes.

| Upstream | Our build | Package |
|---|---|---|
| `9.0.1.5` | 0 | `9.0.1.500` |
| `9.0.1.5` | 1 | `9.0.1.501` |
| `8.1.2.5` | 0 | `8.1.2.500` |

The two counters occupy separate digit ranges, so they cannot drift into each other and the
mapping is reversible: `upstream_z = z / 100`, `our_build = z % 100`. This is why a shared
counter with a `max(upstream, last+1)` rule was rejected — shipping three packaging fixes
against one upstream build leaves the package version permanently ahead, and a version like
`9.0.1.4` would then denote upstream build 2.

`our_build` is computed at release time from existing `v*` git tags: the highest `z` already
tagged for this `w.x.y` whose `z / 100` equals the current `upstream_z`, plus one; zero if none.

**AssemblyVersion is set separately** as `{major}.0.0.0`. A four-part `AssemblyVersion` caps each
component at 65534 (CS7034); package versions have no such limit. The existing `build.yml`
already does this.

## Multi-series tracking

`versions.json` at the repository root:

```json
{
  "9.0": "9.0.1.5",
  "8.1": "8.1.2.5"
}
```

One `main` branch tracks every series. Branch-per-series was rejected: now that the FFmpeg build
is gone, the only difference between series is a version string, so branches would mean
cherry-picking every workflow fix N times for no benefit.

Adding or dropping a tracked series is a one-line edit.

## Workflows

### `check-updates.yml` — weekly and on demand

1. List all upstream releases, group by FFmpeg `major.minor`.
2. For each key in `versions.json`, find the highest upstream tag in that series.
3. For each series that moved, open a PR updating that one key.

Series are independent — two PRs can be open at once. `releases/latest` is never consulted; it
points at whichever series published most recently and would silently abandon the other.

### `ci.yml` — PR gate

Packs against `versions.json` at version `0.0.0-pr`, runs `verify-packages.sh`, and does not
push. This is where a malformed staging change is caught.

### `release.yml` — tag-triggered, three phases

1. **`publish-base`** — helper + 44 runtime + 4 Apple packages.
2. **`publish-meta`** — the 4 metas. Retried with backoff, because they cannot restore their
   transitive dependencies until nuget.org has indexed phase 1.
3. **`create-release`** — tag `v{version}` and create a GitHub Release.

Every download is verified against the release's `SHA256SUMS` before extraction.

## Verification

`scripts/verify-packages.sh` inspects built `.nupkg` files without publishing, asserting:

- no symlinked or duplicate libraries survived staging (the size regression this guards against
  is roughly 3x)
- no `include/` directory in any package
- `legal/` present in every platform package
- `libc++_shared.so` present in both Android packages
- every runtime package's payload sits under `runtimes/{rid}/native/`
- each meta's dependency groups match the TFM table above

Both must run on Linux. On Windows, `tar` cannot create symlinks, so the bug the first
assertion guards against does not reproduce — the desktop normalization cannot be meaningfully
tested there. Local verification runs under WSL (Ubuntu 24.04); the macOS and Android paths are
exercised in CI.

`RIDS` and `CELLS` are overridable so a local run can pack one package instead of 53:

```bash
RIDS="linux-musl-x64" CELLS="gplv2" \
  ./scripts/pack.sh 9.0.1.5 0.0.0-local --output ./nupkgs --phase base
```

## Breaking changes

| Change | Effect |
|---|---|
| `DevEnvy.FFmpeg.Binaries.LGPL` unlisted | Existing pinned references still resolve; the ID leaves search. README points at `.LGPLv2`. |
| Binaries move from `ffmpeg/{rid}/` to `runtimes/{rid}/native/` | Anyone reading the old path directly breaks. `FFmpegBinaries.GetLibraryPath()` consumers do not. |
| Helper assembly moves to its own package | A consumer referencing only a cell package no longer gets `FFmpegBinaries`; the metas depend on the helper, so meta consumers are unaffected. |

## Risks and items to validate in CI

1. **Android native asset packing.** `runtimes/android-{arm64,x64}/native/*.so` is the documented
   convention and SkiaSharp ships this shape, but it is not verified here. A real `net10.0-android`
   build must confirm the `.so` files land in the APK.
2. **iOS `NativeReference` wiring.** The number of `NativeReference` items, `Kind="Framework"`
   versus `Kind="Static"`, and simulator slice selection all need a real `net10.0-ios` build on a
   macOS runner. This is the least-verified part of the design.
3. **53 packages x 2 live series** is up to 106 pushes if both series bump at once. Phase 2's
   indexing retry must tolerate that; if nuget.org rate-limits, phases may need batching.
4. **`maccatalyst-*` is unsupported.** A MAUI app targeting Mac Catalyst gets no binaries from
   the meta's dependency groups. This should fail with a clear message rather than silently.

Per the agreed sequencing, implementation proceeds on a branch behind a draft PR so CI exercises
the macOS and Android paths that cannot be checked under WSL. Nothing publishes until all 53
packages build and verify.
