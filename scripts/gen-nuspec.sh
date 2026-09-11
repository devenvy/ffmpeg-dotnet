#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# gen-nuspec.sh — emit one .nuspec into .nuspec-gen/
#
#   gen-nuspec.sh <kind> <Cell> <rid> <version> <ffmpeg-version>
#
# kind: runtime | apple | meta-all | meta-rid
#
# These packages are file containers plus metadata, so they are packed from
# hand-written nuspecs rather than csprojs. That keeps per-TFM metadata and
# runtime.json under direct control, and means CI needs no MAUI workloads
# installed just to emit an iOS package's manifest.
# ==============================================================================

KIND="${1:?kind}"
CELL="${2:?cell}"
RID="${3:-}"
VERSION="${4:?version}"
FFMPEG_VERSION="${5:?ffmpeg version}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${REPO_ROOT}/.nuspec-gen"
STAGING="${REPO_ROOT}/staging/${CELL}"
# Paths written INTO the nuspec are relative to NuspecBasePath, which pack.sh
# sets to the repo root (as ../.. from the stub project). They must stay relative:
# an absolute /d/... is rewritten to D:\d\... by Git Bash before dotnet sees it.
REL_STAGING="staging/${CELL}"
mkdir -p "${OUT}"

# Upstream cell -> SPDX expression. Upstream's "v2" cells are LGPL-2.1 / GPL-2.0.
declare -A SPDX=(
  [LGPLv2]="LGPL-2.1-or-later"
  [LGPLv3]="LGPL-3.0-or-later"
  [GPLv2]="GPL-2.0-or-later"
  [GPLv3]="GPL-3.0-or-later"
)

ALL_RIDS=(win-x64 win-arm64 linux-x64 linux-arm64 linux-arm linux-musl-x64 linux-musl-arm64 osx-x64 osx-arm64 android-arm64 android-x64)

COMMON_META="    <version>${VERSION}</version>
    <authors>DevEnvy</authors>
    <owners>DevEnvy</owners>
    <license type=\"expression\">${SPDX[${CELL}]}</license>
    <projectUrl>https://github.com/devenvy/ffmpeg-dotnet</projectUrl>
    <repository type=\"git\" url=\"https://github.com/devenvy/ffmpeg-dotnet\" />
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <tags>ffmpeg native media video audio</tags>"

case "${KIND}" in

  ###########################################################################
  # runtime — one platform's native payload under runtimes/{rid}/native/
  ###########################################################################
  runtime)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.${RID}"
    TARGETS="${OUT}/${ID}.targets"

    # ffmpeg/ffprobe lose their executable bit in transit: a .nupkg is a zip and
    # NuGet does not carry Unix permissions, so an extracted ffmpeg comes out
    # mode 0644 and Process.Start fails with EACCES. Shared libraries are
    # unaffected (dlopen needs read, not execute), so this only restores +x on
    # the two executables.
    cat > "${TARGETS}" <<TARGETSEOF
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <Target Name="DevEnvyFFmpegRestoreExecuteBit_$(echo "${RID}" | tr '-' '_')"
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

    cat > "${OUT}/${ID}.nuspec" <<NUSPECEOF
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/01/nuspec.xsd">
  <metadata>
    <id>${ID}</id>
${COMMON_META}
    <description>FFmpeg ${FFMPEG_VERSION} ${CELL} native binaries for ${RID}. Reference DevEnvy.FFmpeg.Binaries.${CELL} or .Rid instead of this package directly.</description>
  </metadata>
  <files>
    <file src="${REL_STAGING}/${RID}/native/**" target="runtimes/${RID}/native" />
    <file src="${REL_STAGING}/${RID}/legal/**" target="legal" />
    <file src=".nuspec-gen/$(basename "${TARGETS}")" target="buildTransitive/${ID}.targets" />
    <file src=".nuspec-gen/$(basename "${TARGETS}")" target="build/${ID}.targets" />
  </files>
</package>
NUSPECEOF
    ;;

  ###########################################################################
  # apple — xcframeworks injected as NativeReference items
  #
  # RID-native probing does not apply on iOS: .NET for iOS consumes native code
  # through @(NativeReference), and Xcode selects the device or simulator slice
  # from the xcframework and strips the unused one from the shipped app.
  ###########################################################################
  apple)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}.Apple"
    TARGETS="${OUT}/${ID}.targets"

    {
      echo '<?xml version="1.0" encoding="utf-8"?>'
      echo '<Project>'
      # shellcheck disable=SC2016  # $(TargetPlatformIdentifier) is MSBuild syntax
      echo '  <ItemGroup Condition="'"'"'$(TargetPlatformIdentifier)'"'"' == '"'"'ios'"'"'">'
      for fw in "${STAGING}"/ios/*.xcframework; do
        [[ -d "${fw}" ]] || continue
        echo "    <NativeReference Include=\"\$(MSBuildThisFileDirectory)../frameworks/$(basename "${fw}")\" Kind=\"Framework\" />"
      done
      echo '  </ItemGroup>'
      echo '</Project>'
    } > "${TARGETS}"

    cat > "${OUT}/${ID}.nuspec" <<NUSPECEOF
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/01/nuspec.xsd">
  <metadata>
    <id>${ID}</id>
${COMMON_META}
    <description>FFmpeg ${FFMPEG_VERSION} ${CELL} xcframeworks for iOS (device and simulator). Reference DevEnvy.FFmpeg.Binaries.${CELL}.Rid instead of this package directly.</description>
  </metadata>
  <files>
    <file src="${REL_STAGING}/ios/*.xcframework/**" target="frameworks" />
    <file src="${REL_STAGING}/ios/legal/**" target="legal" />
    <file src=".nuspec-gen/$(basename "${TARGETS}")" target="buildTransitive/${ID}.targets" />
    <file src=".nuspec-gen/$(basename "${TARGETS}")" target="build/${ID}.targets" />
  </files>
</package>
NUSPECEOF
    ;;

  ###########################################################################
  # meta-all — depends on every RID-native package.
  #
  # Restores and copies every platform regardless of what is being built, which
  # is correct for a genuinely portable app and expensive for everything else.
  # It ships the trim targets so a consumer can narrow the copy without giving
  # up the RID-less build; .Rid narrows the restore itself.
  #
  # Apple is deliberately NOT a dependency here: an iOS head always builds with
  # a RID, so it is served by .Rid, and this keeps 36 MB of xcframeworks out of
  # every server app.
  ###########################################################################
  meta-all)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}"
    TARGETS="${OUT}/${ID}.targets"
    cp "${REPO_ROOT}/src/Packaging/trim.targets" "${TARGETS}"

    {
      echo '<?xml version="1.0" encoding="utf-8"?>'
      echo '<package xmlns="http://schemas.microsoft.com/packaging/2013/01/nuspec.xsd">'
      echo '  <metadata>'
      echo "    <id>${ID}</id>"
      echo "${COMMON_META}"
      echo "    <description>FFmpeg ${FFMPEG_VERSION} ${CELL} native binaries for every supported platform. For a single-platform restore use DevEnvy.FFmpeg.Binaries.${CELL}.Rid instead.</description>"
      echo '    <dependencies>'
      echo '      <group targetFramework="netstandard2.0">'
      echo "        <dependency id=\"DevEnvy.FFmpeg.Binaries\" version=\"[${VERSION}]\" />"
      for r in "${ALL_RIDS[@]}"; do
        echo "        <dependency id=\"${ID}.Runtime.${r}\" version=\"[${VERSION}]\" />"
      done
      echo '      </group>'
      echo '    </dependencies>'
      echo '  </metadata>'
      echo '  <files>'
      echo "    <file src=\".nuspec-gen/$(basename "${TARGETS}")\" target=\"buildTransitive/${ID}.targets\" />"
      echo "    <file src=\".nuspec-gen/$(basename "${TARGETS}")\" target=\"build/${ID}.targets\" />"
      echo '  </files>'
      echo '</package>'
    } > "${OUT}/${ID}.nuspec"
    ;;

  ###########################################################################
  # meta-rid — RID-conditional dependencies via runtime.json
  #
  # NuGet resolves these during restore, so a build that names a RID downloads
  # exactly one platform instead of all twelve. Verified: it fires for both
  # $(RuntimeIdentifier) and a project-declared $(RuntimeIdentifiers) list (the
  # multi-ABI shape .NET Android uses), and unlike a conditional PackageReference
  # it is immune to the difference between `-r` and `-p:RuntimeIdentifier=`.
  #
  # A RID-less build resolves no platform at all, which is why meta-all exists.
  ###########################################################################
  meta-rid)
    ID="DevEnvy.FFmpeg.Binaries.${CELL}.Rid"
    BASE="DevEnvy.FFmpeg.Binaries.${CELL}"
    RJ="${OUT}/${ID}.runtime.json"
    GUARD="${OUT}/${ID}.targets"

    {
      echo '{'
      echo '  "runtimes": {'
      first=1
      for r in "${ALL_RIDS[@]}"; do
        [[ ${first} -eq 0 ]] && echo ','
        first=0
        printf '    "%s": { "%s": { "%s.Runtime.%s": "[%s]" } }' "${r}" "${ID}" "${BASE}" "${r}" "${VERSION}"
      done
      for r in ios-arm64 iossimulator-arm64; do
        echo ','
        printf '    "%s": { "%s": { "%s.Apple": "[%s]" } }' "${r}" "${ID}" "${BASE}" "${VERSION}"
      done
      echo ''
      echo '  }'
      echo '}'
    } > "${RJ}"

    # Without a RID this package resolves no binaries at all. Say so at build
    # time rather than letting it surface as a DllNotFoundException at runtime.
    cat > "${GUARD}" <<'GUARDEOF'
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <Target Name="DevEnvyFFmpegRidRequired" BeforeTargets="Build"
          Condition="'$(RuntimeIdentifier)' == '' AND '$(RuntimeIdentifiers)' == ''">
    <Warning Code="DEVFFM001"
             Text="DevEnvy.FFmpeg.Binaries.*.Rid resolves native binaries per RuntimeIdentifier, and this project sets neither RuntimeIdentifier nor RuntimeIdentifiers, so no FFmpeg binaries were restored. Set a RID, or reference the DevEnvy.FFmpeg.Binaries.* package instead, which carries every platform." />
  </Target>
</Project>
GUARDEOF

    cat > "${OUT}/${ID}.nuspec" <<NUSPECEOF
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/01/nuspec.xsd">
  <metadata>
    <id>${ID}</id>
${COMMON_META}
    <description>FFmpeg ${FFMPEG_VERSION} ${CELL} native binaries, restored for the RuntimeIdentifier being built instead of all platforms. Requires a RID; for a RID-less build reference DevEnvy.FFmpeg.Binaries.${CELL}.</description>
    <dependencies>
      <group targetFramework="netstandard2.0">
        <dependency id="DevEnvy.FFmpeg.Binaries" version="[${VERSION}]" />
      </group>
    </dependencies>
  </metadata>
  <files>
    <file src=".nuspec-gen/$(basename "${RJ}")" target="runtime.json" />
    <file src=".nuspec-gen/$(basename "${GUARD}")" target="buildTransitive/${ID}.targets" />
    <file src=".nuspec-gen/$(basename "${GUARD}")" target="build/${ID}.targets" />
  </files>
</package>
NUSPECEOF
    ;;

  *) echo "Unknown kind: ${KIND}" >&2; exit 1 ;;
esac
