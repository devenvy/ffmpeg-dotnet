# DevEnvy.FFmpeg.Binaries

Locates the native FFmpeg binaries shipped by the `DevEnvy.FFmpeg.Binaries.*.Runtime.*`
packages. This package contains no binaries itself.

Reference a platform package to get them. Every platform package depends on this one, so a
single reference gives you both:

```xml
<ItemGroup Condition="'$(RuntimeIdentifier)' == ''">
  <PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.All" Version="9.0.1.500" />
</ItemGroup>
<ItemGroup Condition="'$(RuntimeIdentifier)' != ''">
  <PackageReference Include="DevEnvy.FFmpeg.Binaries.LGPLv2.Runtime.$(RuntimeIdentifier)" Version="9.0.1.500" />
</ItemGroup>
```

Four license variants are published: `LGPLv2`, `LGPLv3`, `GPLv2`, `GPLv3`.

```csharp
var dir = FFmpegBinaries.GetLibraryPath();
DynamicallyLoadedBindings.LibrariesPath = dir;
DynamicallyLoadedBindings.Initialize();
```

`GetFFmpegPath()` and `GetFFprobePath()` return `null` on Android and iOS, whose packages
ship libraries only.

Staging keeps one name per shared library - the SONAME - so default P/Invoke probing for an
unversioned name (`[DllImport("avcodec")]`) will not find it. Use FFmpeg.AutoGen's dynamic
loader, or register a `DllImportResolver` that resolves to the versioned name.
