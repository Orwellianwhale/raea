# This fork: raea on Windows on ARM

Upstream raea (shinyobjectz/raea) ships Windows builds for x86_64 only, and its installer refuses ARM64 machines. This
fork adds:

| File | What |
|---|---|
| `tools/windows/install.ps1` | An installer that knows ARM64: on an ARM PC it takes the native `windows-arm64` build when a release has one, else the `windows-x86_64` build, which runs under Windows' x64 emulation. `RAEA_REPO=<owner>/raea` reads this fork's releases first. On x86_64 it behaves like upstream's. |
| `.github/workflows/windows-builds.yml` | Builds `windows-arm64` (on GitHub's `windows-11-arm` runner) and `windows-x86_64` from any ref and publishes both on a pre-release of this fork. Run by hand. |
| `tools/release.sh` | Packs a `windows-arm64` zip when the host Rust is `aarch64-pc-windows-msvc`; `RAEA_PLATFORM` overrides the name; `RAEA_SKILLS_GATE=skip` for a fork build (the skills are upstream's, unchanged); `RAEA_RELEASE_CHECK=skip` where a runner can't render; Windows' own `tar` when there's no 7-Zip. |

Install on either machine (PowerShell):

```powershell
$env:RAEA_REPO = "<owner>/raea"
irm https://raw.githubusercontent.com/<owner>/raea/windows-arm64/tools/windows/install.ps1 | iex
```

The ARM64 machine needs the Visual C++ Redistributable for ARM64 (`https://aka.ms/vs/17/release/vc_redist.arm64.exe`)
for the native build. The licence is upstream's (FSL-1.1-ALv2).
