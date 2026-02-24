using FFmpeg.AutoGen.Abstractions;
using FFmpeg.AutoGen.Bindings.DynamicallyLoaded;
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
            var nativePath = Path.Combine(AppContext.BaseDirectory, "runtimes", rid, "native");

            if (!Directory.Exists(nativePath))
                nativePath = Path.Combine(AppContext.BaseDirectory, "runtimes", rid);

            // Fall back to base directory (for RID-specific publish)
            if (!Directory.Exists(nativePath))
                nativePath = AppContext.BaseDirectory;

            return nativePath;
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

        /// <summary>
        /// Register FFMPEG binaries.
        /// </summary>
        public static void RegisterFFmpegBinaries()
        {
            EnsureLibraryPath();

            DynamicallyLoadedBindings.LibrariesPath = GetLibraryPath();
            DynamicallyLoadedBindings.Initialize();

            var ffmpegLogLevelStr = Environment.GetEnvironmentVariable("FFMPEG_LOG_LEVEL");

            int ffmpegLogLevel = ffmpegLogLevelStr?.ToUpper() switch
            {
                "QUIET" => ffmpeg.AV_LOG_QUIET,
                "PANIC" => ffmpeg.AV_LOG_PANIC,
                "FATAL" => ffmpeg.AV_LOG_FATAL,
                "ERROR" => ffmpeg.AV_LOG_ERROR,
                "WARNING" => ffmpeg.AV_LOG_WARNING,
                "INFO" => ffmpeg.AV_LOG_INFO,
                "VERBOSE" => ffmpeg.AV_LOG_VERBOSE,
                "DEBUG" => ffmpeg.AV_LOG_DEBUG,
                "TRACE" => ffmpeg.AV_LOG_TRACE,
                _ => ffmpeg.AV_LOG_QUIET,
            };

            ffmpeg.av_log_set_level(ffmpegLogLevel);
        }

        private static void EnsureLibraryPath()
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                return;

            var libraryPath = GetLibraryPath();
            var currentPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;

            if (!currentPath.StartsWith(libraryPath + ";", StringComparison.OrdinalIgnoreCase)
                && !currentPath.EndsWith(";" + libraryPath, StringComparison.OrdinalIgnoreCase)
                && currentPath.IndexOf(";" + libraryPath + ";", StringComparison.OrdinalIgnoreCase) < 0)
            {
                Environment.SetEnvironmentVariable("PATH", libraryPath + ";" + currentPath);
            }

            SetDllDirectory(libraryPath);
        }

        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool SetDllDirectory(string? lpPathName);

        private static string GetRuntimeIdentifier()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                return "win-x64";

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                // Detect musl (Alpine) vs glibc
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

                    if (output.IndexOf("musl", StringComparison.OrdinalIgnoreCase) >= 0)
                        return "linux-musl-x64";
                }
                catch { }

                return "linux-x64";
            }

            throw new PlatformNotSupportedException();
        }
    }
}
