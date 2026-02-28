using System;
using System.IO;
using System.Runtime.InteropServices;

namespace DevEnvy.Binaries.LGPL
{
    public static class FFmpegBinaries
    {
        /// <summary>
        /// Gets the path to the FFmpeg native libraries based on the current runtime identifier (RID).
        /// Falls back to the application base directory for RID-specific publish layouts.
        /// </summary>
        public static string GetLibraryPath()
        {
            var rid = GetRuntimeIdentifier();

            var nativePath = Path.Combine(AppContext.BaseDirectory, "ffmpeg", rid);
            if (Directory.Exists(nativePath))
                return nativePath;

            // Fall back to base directory (for RID-specific publish)
            return AppContext.BaseDirectory;
        }

        /// <summary>
        /// Gets the full path to the ffmpeg executable.
        /// </summary>
        public static string GetFFmpegPath()
        {
            var name = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "ffmpeg.exe" : "ffmpeg";
            return Path.Combine(GetLibraryPath(), name);
        }

        /// <summary>
        /// Gets the full path to the ffprobe executable.
        /// </summary>
        public static string GetFFprobePath()
        {
            var name = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "ffprobe.exe" : "ffprobe";
            return Path.Combine(GetLibraryPath(), name);
        }

        private static string GetRuntimeIdentifier()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                return RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "win-arm64" : "win-x64";

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                // Detect musl (Alpine) vs glibc
                var isMusl = false;
                try
                {
                    var process = new System.Diagnostics.Process
                    {
                        StartInfo = new System.Diagnostics.ProcessStartInfo
                        {
                            FileName = "ldd",
                            Arguments = "--version",
                            RedirectStandardError = true,
                            RedirectStandardOutput = true,
                            UseShellExecute = false,
                            CreateNoWindow = true
                        }
                    };
                    process.Start();
                    var output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    isMusl = output.IndexOf("musl", StringComparison.OrdinalIgnoreCase) >= 0;
                }
                catch { }

                var arch = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";
                return isMusl ? $"linux-musl-{arch}" : $"linux-{arch}";
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                return RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "osx-arm64" : "osx-x64";

            throw new PlatformNotSupportedException();
        }
    }
}
