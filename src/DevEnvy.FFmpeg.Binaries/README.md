# DevEnvy.FFmpeg.Binaries

Locates the native FFmpeg binaries shipped by the `DevEnvy.FFmpeg.Binaries.*` packages.

This package contains no binaries itself. Reference a license-cell package to get those:

| Package | FFmpeg build |
|---|---|
| `DevEnvy.FFmpeg.Binaries.LGPLv2` | LGPL v2.1 — App-Store safe, no Vulkan |
| `DevEnvy.FFmpeg.Binaries.LGPLv3` | LGPL v3 |
| `DevEnvy.FFmpeg.Binaries.GPLv2`  | GPL v2 |
| `DevEnvy.FFmpeg.Binaries.GPLv3`  | GPL v3 |

```csharp
var dir = FFmpegBinaries.GetLibraryPath();
DynamicallyLoadedBindings.LibrariesPath = dir;
DynamicallyLoadedBindings.Initialize();
```

`GetFFmpegPath()` and `GetFFprobePath()` return `null` on Android and iOS, whose packages ship
libraries only — upstream builds those platforms to be linked into an app, not shelled out to.
