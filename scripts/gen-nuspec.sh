#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# gen-nuspec.sh <kind> <Cell> <rid> <version> <ffmpeg-version>
#
# kind:
#   runtime  emit the .targets for one platform payload package
#   ios      emit the .targets for one Apple RID payload package
#   all      emit the .nuspec for DevEnvy.FFmpeg.Binaries.<Cell>.All
#
# Payload packages are packed from csprojs (src/Packaging/{Runtime,Apple}.csproj)
# because their file globbing needs %(RecursiveDir). Only the dependency-only
# .All meta is packed from a hand-written nuspec.
# ==============================================================================

KIND="${1:?kind}"
CELL="${2:?cell}"
RID="${3:-}"
VERSION="${4:?version}"
FFMPEG_VERSION="${5:?ffmpeg version}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${REPO_ROOT}/.nuspec-gen"
mkdir -p "${OUT}"

declare -A SPDX=(
  [LGPLv2]="LGPL-2.1-or-later"
  [LGPLv3]="LGPL-3.0-or-later"
  [GPLv2]="GPL-2.0-or-later"
  [GPLv3]="GPL-3.0-or-later"
)

# Every platform that gets its own package. "ios" is one of them: it carries
# xcframeworks rather than runtimes/{rid}/native, but to a consumer it is simply
# the iOS payload, so it is named like its siblings.
ALL_RIDS=(win-x64 win-arm64 linux-x64 linux-arm64 linux-arm linux-musl-x64
          linux-musl-arm64 osx-x64 osx-arm64 android-arm64 android-x64
          ios-arm64 iossimulator-arm64)

case "${KIND}" in

  runtime)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.${RID}"
    SAFE="$(echo "${RID}" | tr '.-' '__')"
    # ffmpeg/ffprobe arrive mode 0644 - a .nupkg is a zip and carries no Unix
    # permissions, so Process.Start fails with EACCES without this. Shared
    # libraries are unaffected: dlopen needs read, not execute.
    cat > "${OUT}/${ID}.targets" <<TARGETSEOF
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <Target Name="DevEnvyFFmpegRestoreExecuteBit_${SAFE}"
          AfterTargets="Build;Publish"
          Condition="'\$(OS)' != 'Windows_NT'">
    <ItemGroup>
      <_DevEnvyFFmpegTool Include="\$(OutDir)**/ffmpeg;\$(OutDir)**/ffprobe" />
      <_DevEnvyFFmpegTool Include="\$(PublishDir)**/ffmpeg;\$(PublishDir)**/ffprobe" Condition="'\$(PublishDir)' != ''" />
    </ItemGroup>
    <Exec Command="chmod +x %(_DevEnvyFFmpegTool.FullPath)"
          Condition="'@(_DevEnvyFFmpegTool)' != ''"
          ContinueOnError="true" />
  </Target>
</Project>
TARGETSEOF
    ;;

  ios)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.${RID}"
    STAGING="${REPO_ROOT}/staging/${CELL}/${RID}/frameworks"
    # RID-native probing does not apply on Apple platforms: .NET consumes native
    # code through @(NativeReference). Each package carries only its own slice,
    # so the reference is a plain .framework rather than a fat .xcframework.
    case "${RID}" in
      ios*|maccatalyst*) PLATFORM="${RID%%-*}" ;;
      *) echo "Unexpected Apple RID: ${RID}" >&2; exit 1 ;;
    esac
    [[ "${PLATFORM}" == "iossimulator" ]] && PLATFORM="ios"
    {
      echo '<?xml version="1.0" encoding="utf-8"?>'
      echo '<Project>'
      echo "  <ItemGroup Condition=\"'\$(TargetPlatformIdentifier)' == '${PLATFORM}'\">"
      for fw in "${STAGING}"/*.framework; do
        [[ -d "${fw}" ]] || continue
        echo "    <NativeReference Include=\"\$(MSBuildThisFileDirectory)../frameworks/$(basename "${fw}")\" Kind=\"Framework\" />"
      done
      echo '  </ItemGroup>'
      echo '</Project>'
    } > "${OUT}/${ID}.targets"
    ;;

  all)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.All"
    cp "${REPO_ROOT}/src/Packaging/trim.targets" "${OUT}/${ID}.targets"
    {
      echo '<?xml version="1.0" encoding="utf-8"?>'
      echo '<package xmlns="http://schemas.microsoft.com/packaging/2013/01/nuspec.xsd">'
      echo '  <metadata>'
      echo "    <id>${ID}</id>"
      echo "    <version>${VERSION}</version>"
      echo '    <authors>DevEnvy</authors>'
      echo '    <owners>DevEnvy</owners>'
      echo "    <license type=\"expression\">${SPDX[${CELL}]}</license>"
      echo '    <projectUrl>https://github.com/devenvy/ffmpeg-dotnet</projectUrl>'
      echo '    <repository type="git" url="https://github.com/devenvy/ffmpeg-dotnet" />'
      echo '    <requireLicenseAcceptance>false</requireLicenseAcceptance>'
      echo '    <tags>ffmpeg native media video audio</tags>'
      echo "    <description>FFmpeg ${FFMPEG_VERSION} ${CELL} native binaries for every supported platform. Reference this when the build sets no RuntimeIdentifier; for a single-platform restore reference DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.&lt;rid&gt; instead.</description>"
      echo '    <dependencies>'
      echo '      <group targetFramework="netstandard2.0">'
      echo "        <dependency id=\"DevEnvy.FFmpeg.Binaries\" version=\"[${VERSION}]\" />"
      for r in "${ALL_RIDS[@]}"; do
        echo "        <dependency id=\"DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.${r}\" version=\"[${VERSION}]\" />"
      done
      echo '      </group>'
      echo '    </dependencies>'
      echo '  </metadata>'
      echo '  <files>'
      echo "    <file src=\".nuspec-gen/${ID}.targets\" target=\"buildTransitive/${ID}.targets\" />"
      echo "    <file src=\".nuspec-gen/${ID}.targets\" target=\"build/${ID}.targets\" />"
      echo '  </files>'
      echo '</package>'
    } > "${OUT}/${ID}.nuspec"
    ;;

  *) echo "Unknown kind: ${KIND}" >&2; exit 1 ;;
esac
