#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# new-mobile-test.sh <android|ios> <feed-dir> <rid>
#
# Scaffolds a minimal MAUI-less mobile head that references the packed FFmpeg
# package, so CI can build it and inspect what the platform SDK embedded.
#
# Android and iOS cannot run the console smoke test, and the thing worth proving
# is not "does a console app start" but "does the platform SDK pick the payload
# up and put it in the app". The APK's lib/<abi>/ and the .app's Frameworks/ are
# exactly where the runtime linker looks, so their contents are the assertion.
# ==============================================================================

PLATFORM="${1:?Usage: new-mobile-test.sh <android|ios> <feed-dir> <rid>}"
FEED="${2:?feed dir}"
RID="${3:?rid}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEED_ABS="$(cd "${FEED}" && pwd)"
OUT="${REPO_ROOT}/.mobile/${PLATFORM}"

PKG_CELL="${PKG_CELL:-LGPLv2}"
PKG_VERSION="${PKG_VERSION:-0.0.0-ci}"

rm -rf "${OUT}"
mkdir -p "${OUT}"

cat > "${OUT}/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="${FEED_ABS}" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <clear />
    <packageSource key="local"><package pattern="DevEnvy.*" /></packageSource>
    <packageSource key="nuget.org"><package pattern="*" /></packageSource>
  </packageSourceMapping>
</configuration>
EOF

case "${PLATFORM}" in
  android)
    cat > "${OUT}/MobileTest.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0-android</TargetFramework>
    <SupportedOSPlatformVersion>28.0</SupportedOSPlatformVersion>
    <OutputType>Exe</OutputType>
    <Nullable>enable</Nullable>
    <ApplicationId>com.devenvy.ffmpeg.mobiletest</ApplicationId>
    <RuntimeIdentifiers>${RID}</RuntimeIdentifiers>
    <AndroidPackageFormat>apk</AndroidPackageFormat>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="DevEnvy.FFmpeg.Binaries.${PKG_CELL}.Runtime.${RID}" Version="${PKG_VERSION}" />
  </ItemGroup>
</Project>
EOF
    mkdir -p "${OUT}/Properties"
    cat > "${OUT}/MainActivity.cs" <<'EOF'
using Android.App;
using Android.OS;

namespace MobileTest
{
    [Activity(Label = "MobileTest", MainLauncher = true)]
    public class MainActivity : Activity
    {
        protected override void OnCreate(Bundle? savedInstanceState)
        {
            base.OnCreate(savedInstanceState);
        }
    }
}
EOF
    cat > "${OUT}/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="MobileTest" />
</manifest>
EOF
    ;;

  ios)
    cat > "${OUT}/MobileTest.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0-ios</TargetFramework>
    <SupportedOSPlatformVersion>13.0</SupportedOSPlatformVersion>
    <OutputType>Exe</OutputType>
    <Nullable>enable</Nullable>
    <ApplicationId>com.devenvy.ffmpeg.mobiletest</ApplicationId>
    <RuntimeIdentifier>${RID}</RuntimeIdentifier>
    <CodesignKey></CodesignKey>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="DevEnvy.FFmpeg.Binaries.${PKG_CELL}.Runtime.${RID}" Version="${PKG_VERSION}" />
  </ItemGroup>
</Project>
EOF
    cat > "${OUT}/Main.cs" <<'EOF'
using UIKit;
using Foundation;

namespace MobileTest
{
    public class Application
    {
        public static void Main(string[] args) => UIApplication.Main(args, null, typeof(AppDelegate));
    }

    [Register(nameof(AppDelegate))]
    public class AppDelegate : UIApplicationDelegate
    {
        public override UIWindow? Window { get; set; }
    }
}
EOF
    cat > "${OUT}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.devenvy.ffmpeg.mobiletest</string>
  <key>CFBundleName</key><string>MobileTest</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>13.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict>
</plist>
EOF
    ;;

  *)
    echo "Unknown platform: ${PLATFORM}" >&2
    exit 1
    ;;
esac

echo "Scaffolded ${PLATFORM} head for ${RID} in ${OUT}"
