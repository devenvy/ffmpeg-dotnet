using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace DevEnvy.FFmpeg.Binaries
{
    /// <summary>
    /// Locates the native FFmpeg binaries shipped by the <c>DevEnvy.FFmpeg.Binaries.*</c> packages.
    /// </summary>
    /// <remarks>
    /// The binaries ship under NuGet's standard <c>runtimes/{rid}/native/</c> layout, which the SDK
    /// lays out two different ways depending on how the consuming app is built:
    /// <list type="bullet">
    /// <item>a RID-agnostic build keeps them nested, under <c>runtimes/{rid}/native/</c>;</item>
    /// <item>a RID-specific build or publish flattens the matching RID into the output root.</item>
    /// </list>
    /// Both are probed, nested first, so the same call works in either layout.
    /// </remarks>
    public static class FFmpegBinaries
    {
        private const string FFmpegExecutableName = "ffmpeg";
        private const string FFprobeExecutableName = "ffprobe";

        /// <summary>
        /// Gets the directory holding the native FFmpeg libraries for the current platform.
        /// </summary>
        /// <remarks>
        /// Falls back to <see cref="AppContext.BaseDirectory"/> when no nested
        /// <c>runtimes/{rid}/native/</c> directory exists, which is the layout a RID-specific
        /// publish produces. The fallback is returned without checking that it holds any
        /// libraries, so callers that need certainty should use <see cref="TryGetLibraryPath"/>.
        /// </remarks>
        public static string GetLibraryPath()
        {
            return TryGetLibraryPath(out var path) ? path : AppContext.BaseDirectory;
        }

        /// <summary>
        /// Attempts to locate the native FFmpeg libraries, verifying that the directory found
        /// actually contains at least one of them.
        /// </summary>
        /// <param name="path">The directory holding the libraries, when found.</param>
        /// <returns><see langword="true"/> if a directory containing FFmpeg libraries was found.</returns>
        public static bool TryGetLibraryPath(out string path)
        {
            var baseDirectory = AppContext.BaseDirectory;

            foreach (var rid in GetCandidateRuntimeIdentifiers())
            {
                var candidate = Path.Combine(baseDirectory, "runtimes", rid, "native");
                if (ContainsFFmpegLibraries(candidate))
                {
                    path = candidate;
                    return true;
                }
            }

            // A RID-specific publish flattens the matching RID into the output root.
            if (ContainsFFmpegLibraries(baseDirectory))
            {
                path = baseDirectory;
                return true;
            }

            // Apple platforms do not use runtimes/{rid}/native at all: the
            // packages ship .framework bundles that the SDK embeds under
            // Frameworks/ in the app. Each bundle holds its binary under its own
            // name, so the directory itself is what a loader needs.
            var frameworks = Path.Combine(baseDirectory, "Frameworks");
            if (Directory.Exists(frameworks)
                && Directory.EnumerateDirectories(frameworks, "*avutil*.framework").Any())
            {
                path = frameworks;
                return true;
            }

            path = baseDirectory;
            return false;
        }

        /// <summary>
        /// Gets the full path to the <c>ffmpeg</c> executable, or <see langword="null"/> when the
        /// current platform's package ships libraries only.
        /// </summary>
        /// <remarks>
        /// The Android and iOS packages contain no command-line executables — upstream builds those
        /// platforms to be linked into an app, not shelled out to.
        /// </remarks>
        public static string? GetFFmpegPath() => GetExecutablePath(FFmpegExecutableName);

        /// <summary>
        /// Gets the full path to the <c>ffprobe</c> executable, or <see langword="null"/> when the
        /// current platform's package ships libraries only.
        /// </summary>
        /// <inheritdoc cref="GetFFmpegPath" path="/remarks"/>
        public static string? GetFFprobePath() => GetExecutablePath(FFprobeExecutableName);

        private static string? GetExecutablePath(string name)
        {
            var fileName = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? name + ".exe" : name;
            var path = Path.Combine(GetLibraryPath(), fileName);
            return File.Exists(path) ? path : null;
        }

        private static bool ContainsFFmpegLibraries(string directory)
        {
            if (!Directory.Exists(directory))
            {
                return false;
            }

            // Matches avcodec-63.dll, libavcodec.so.63 and libavcodec.63.dylib alike.
            return Directory.EnumerateFiles(directory, "*avcodec*").Any();
        }

        /// <summary>
        /// Yields the RIDs whose <c>runtimes/{rid}/native/</c> directory could serve this process,
        /// most specific first.
        /// </summary>
        private static IEnumerable<string> GetCandidateRuntimeIdentifiers()
        {
            var architecture = GetArchitectureName();

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                yield return "win-" + architecture;
                yield break;
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                yield return "osx-" + architecture;
                yield break;
            }

            if (IsAndroid())
            {
                yield return "android-" + architecture;
                yield break;
            }

            // Linux. Probe musl first when its loader is present, but yield both: a glibc-only
            // package set on a musl host is still worth finding, and vice versa.
            if (IsMusl())
            {
                yield return "linux-musl-" + architecture;
                yield return "linux-" + architecture;
            }
            else
            {
                yield return "linux-" + architecture;
                yield return "linux-musl-" + architecture;
            }
        }

        private static string GetArchitectureName()
        {
            switch (RuntimeInformation.ProcessArchitecture)
            {
                case Architecture.X64: return "x64";
                case Architecture.Arm64: return "arm64";
                case Architecture.Arm: return "arm";
                case Architecture.X86: return "x86";
                default: return RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant();
            }
        }

        private static bool IsAndroid()
        {
#if NET8_0_OR_GREATER
            return OperatingSystem.IsAndroid();
#else
            // Bionic ships a linker at a fixed path that no glibc or musl distribution has.
            return File.Exists("/system/build.prop") || Directory.Exists("/system/app");
#endif
        }

        /// <summary>
        /// Detects a musl libc host by the presence of its dynamic loader.
        /// </summary>
        /// <remarks>
        /// Alpine installs <c>/lib/ld-musl-{arch}.so.1</c>. Probing for the file avoids spawning
        /// <c>ldd</c>, which costs a process launch on every call and is unavailable in minimal
        /// containers.
        /// </remarks>
        private static bool IsMusl()
        {
            try
            {
                return Directory.Exists("/lib")
                    && Directory.EnumerateFiles("/lib", "ld-musl-*.so.1").Any();
            }
            catch (IOException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
        }
    }
}
