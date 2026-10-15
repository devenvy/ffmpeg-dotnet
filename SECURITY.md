# Security

## Supported versions

| Version                                    | Supported                                                      |
| ------------------------------------------ | -------------------------------------------------------------- |
| The latest packages of each tracked series | Yes: fixes ship as a new package version (a packaging rebuild) |
| Older package versions                     | No: update to the latest version of the series you use         |

## Reporting a vulnerability

Please report vulnerabilities privately, through GitHub's private vulnerability reporting:
[report a vulnerability](https://github.com/devenvy/ffmpeg-dotnet/security/advisories/new) (Security, Advisories,
**Report a vulnerability**). Please don't open a public issue. You'll get an answer within a week, and the fix and
advisory are published together.

In scope: the `DevEnvy.FFmpeg.Binaries` helper library, the packaging scripts (what they download from
[devenvy/ffmpeg](https://github.com/devenvy/ffmpeg) releases, how they check it and what they put in each package),
and the workflows that build, verify and publish the packages.

Vulnerabilities in FFmpeg or in the libraries it is built with belong upstream, at
[devenvy/ffmpeg](https://github.com/devenvy/ffmpeg/security/advisories/new); once a fixed build is released there, the
next package release here picks it up.
