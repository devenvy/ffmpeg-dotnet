# DevEnvy.FFmpeg.Binaries native packages

Prebuilt FFmpeg shared libraries (plus the `ffmpeg` and `ffprobe` tools on desktop platforms),
packaged for .NET. Every package depends on `DevEnvy.FFmpeg.Binaries`, which locates the binaries
at run time.

- `DevEnvy.FFmpeg.Binaries.<cell>.Runtime.<rid>`: the binaries for one platform.
- `DevEnvy.FFmpeg.Binaries.<cell>.Runtime.All`: every platform, for builds that set no
  `RuntimeIdentifier`.

Four license variants (cells) are published: `LGPLv2`, `LGPLv3`, `GPLv2`, `GPLv3`. Pick one
and use it everywhere.

```xml
<ItemGroup Condition="'$(RuntimeIdentifier)' == ''">
  <PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.All" Version="9.0.1.500" />
</ItemGroup>
<ItemGroup Condition="'$(RuntimeIdentifier)' != ''">
  <PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.$(RuntimeIdentifier)" Version="9.0.1.500" />
</ItemGroup>
```

```csharp
var dir = FFmpegBinaries.GetLibraryPath();
DynamicallyLoadedBindings.LibrariesPath = dir;
DynamicallyLoadedBindings.Initialize();
```

Use the FFmpeg.AutoGen of the same FFmpeg series as the package (`9.0.*` with `9.0.*`).

Each package ships FFmpeg's `THIRD-PARTY-NOTICES.txt` at its root. Desktop packages also copy it
into your build output as `FFmpeg-THIRD-PARTY-NOTICES.txt`.

Full documentation: https://github.com/devenvy/ffmpeg-dotnet
