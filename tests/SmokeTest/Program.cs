using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using DevEnvy.FFmpeg.Binaries;

namespace SmokeTest
{
    /// <summary>
    /// Proves the shipped binaries work on the platform running this, rather than
    /// merely being present in the package. Three things are checked, and each one
    /// catches a different class of packaging mistake:
    ///
    ///   1. The libraries are where <see cref="FFmpegBinaries"/> says they are.
    ///      Catches a wrong RID probe or a broken runtimes/{rid}/native layout.
    ///   2. A real native function returns a real value. Catches shipping the wrong
    ///      library name — the SONAME dedup keeps exactly one name per library, and
    ///      if that choice were wrong the file would still be present but unloadable.
    ///   3. ffmpeg executes. Catches the lost executable bit, which a .nupkg drops
    ///      silently because a zip carries no Unix permissions.
    /// </summary>
    internal static class Program
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr AvVersionInfo();

        private static int Main()
        {
            var failures = 0;

            Console.WriteLine($"RID        : {RuntimeInformation.RuntimeIdentifier}");
            Console.WriteLine($"OS         : {RuntimeInformation.OSDescription.Trim()}");
            Console.WriteLine($"Arch       : {RuntimeInformation.ProcessArchitecture}");
            Console.WriteLine();

            // 1. Locate
            if (!FFmpegBinaries.TryGetLibraryPath(out var dir))
            {
                Console.Error.WriteLine($"FAIL locate : no FFmpeg libraries found (looked under {dir})");
                return 1;
            }
            Console.WriteLine($"PASS locate : {dir}");

            // 2. Load and call
            var avutil = Directory.EnumerateFiles(dir, "*avutil*")
                .Where(f => !f.EndsWith(".lib", StringComparison.OrdinalIgnoreCase))
                .OrderBy(f => f.Length)
                .FirstOrDefault();

            if (avutil is null)
            {
                Console.Error.WriteLine($"FAIL load   : no avutil library in {dir}");
                failures++;
            }
            else
            {
                try
                {
                    var handle = NativeLibrary.Load(avutil);
                    var export = NativeLibrary.GetExport(handle, "av_version_info");
                    var fn = Marshal.GetDelegateForFunctionPointer<AvVersionInfo>(export);
                    var version = Marshal.PtrToStringAnsi(fn());

                    if (string.IsNullOrWhiteSpace(version))
                    {
                        Console.Error.WriteLine("FAIL load   : av_version_info() returned nothing");
                        failures++;
                    }
                    else
                    {
                        Console.WriteLine($"PASS load   : av_version_info() = {version}  [{Path.GetFileName(avutil)}]");
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"FAIL load   : {Path.GetFileName(avutil)}: {ex.Message}");
                    failures++;
                }
            }

            // 3. Execute. Android and iOS ship libraries only, so absence is expected there.
            var ffmpeg = FFmpegBinaries.GetFFmpegPath();
            if (ffmpeg is null)
            {
                Console.WriteLine("SKIP exec   : no ffmpeg executable in this package (expected on Android and iOS)");
            }
            else
            {
                failures += RunFFmpeg(ffmpeg);
            }

            Console.WriteLine();
            Console.WriteLine(failures == 0 ? "SMOKE TEST PASSED" : $"SMOKE TEST FAILED ({failures} failure(s))");
            return failures == 0 ? 0 : 1;
        }

        private static int RunFFmpeg(string ffmpeg)
        {
            try
            {
                using var process = Process.Start(new ProcessStartInfo
                {
                    FileName = ffmpeg,
                    Arguments = "-hide_banner -version",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                })!;

                var stdout = process.StandardOutput.ReadToEnd();
                var stderr = process.StandardError.ReadToEnd();
                process.WaitForExit(60_000);

                if (process.ExitCode != 0)
                {
                    Console.Error.WriteLine($"FAIL exec   : ffmpeg exited {process.ExitCode}: {stderr.Trim()}");
                    return 1;
                }

                var first = stdout.Split('\n').FirstOrDefault()?.Trim();
                Console.WriteLine($"PASS exec   : {first}");
                return 0;
            }
            catch (Exception ex)
            {
                // A .nupkg is a zip and carries no Unix permissions, so ffmpeg arrives
                // mode 0644 and execve fails with EACCES unless the package's targets
                // restored the bit.
                Console.Error.WriteLine($"FAIL exec   : {ffmpeg}: {ex.Message}");
                return 1;
            }
        }
    }
}
