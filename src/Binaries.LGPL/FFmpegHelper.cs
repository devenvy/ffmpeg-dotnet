using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Binaries.LGPL
{
    public static class FFmpegBinaries
    {
        /// <summary>
        /// Gets the path to the FFmpeg native libraries based on the current runtime identifier (RID).
        /// Falls back to the application base directory for RID-specific publish layouts.
        /// </summary>
        public static string GetPath()
        {
            var rid = GetRuntimeIdentifier();
            var nativePath = Path.Combine(AppContext.BaseDirectory, "runtimes", rid, "native");

            // Fall back to base directory (for RID-specific publish)
            if (!Directory.Exists(nativePath))
                nativePath = AppContext.BaseDirectory;

            return nativePath;
        }

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
