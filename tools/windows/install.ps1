# raea's installer for Windows, in PowerShell, ARM-aware (fork: Windows on ARM support).
#   irm https://raw.githubusercontent.com/<you>/raea/windows-arm64/tools/windows/install.ps1 | iex
#
# Puts the raea engine under ~\.raea, adds its bin folder to your PATH, and adds raea's agent skills to
# ~\.claude\skills. Run it again to update. Windows 10 or 11.
#   - x86_64 machines get the windows-x86_64 build.
#   - ARM64 machines (Snapdragon X and other Windows on ARM PCs) get the native windows-arm64 build when a release has
#     one, and otherwise the x86_64 build, which runs under Windows' x64 emulation (Prism).
#
# $env:RAEA_VERSION = "0.1.0-canary.2" picks a release (by default the newest with a build for this machine);
# RAEA_REPO = "owner/raea" reads that repository's releases first (a fork that builds Windows on ARM), then
# shinyobjectz/raea; RAEA_ARCH = "x86_64" forces the emulated build on ARM; RAEA_PREFIX moves ~\.raea; RAEA_NO_SKILLS=1
# leaves the skills out; RAEA_DOWNLOAD serves the releases from somewhere else (a mirror, or a local folder to test).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
function Say($m) { Write-Host "raea: $m" }
# throw, not exit: under `irm | iex` an exit would close the terminal it runs in
function Fail($m) { throw "raea: $m" }
function Fetch($from, $to) { if ($from -match "^https?:") { Invoke-WebRequest $from -OutFile $to -UseBasicParsing } else { Copy-Item $from $to } }

# the machine's own architecture: an emulated PowerShell reports its own in PROCESSOR_ARCHITECTURE, so ask the OS
$os = try { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() } catch { $env:PROCESSOR_ARCHITECTURE }
$machine = switch -regex ($os) { "^(?i)arm64$" { "arm64" } "^(?i)(x64|amd64)$" { "x86_64" } default { "" } }
if (-not $machine) { Fail "raea runs on x86_64 or ARM64 Windows (this is $os)." }
if ($env:RAEA_ARCH) { $machine = $env:RAEA_ARCH }
# the builds to look for, best first: on ARM the native one, then the x86_64 one under emulation
$wanted = if ($machine -eq "arm64") { @("windows-arm64", "windows-x86_64") } else { @("windows-x86_64") }

$repos = @()
if ($env:RAEA_REPO) { $repos += $env:RAEA_REPO }
$repos += "shinyobjectz/raea"
$prefix = if ($env:RAEA_PREFIX) { $env:RAEA_PREFIX } else { Join-Path $HOME ".raea" }

# the first platform in $wanted that a release has, from the newest such release, across the repositories in order
$pick = $null
foreach ($plat in $wanted) {
  foreach ($repo in $repos) {
    try {
      if ($env:RAEA_VERSION) { $rels = @(Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/v$($env:RAEA_VERSION)") }
      else { $rels = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=30" | ForEach-Object { $_ } | Where-Object { $_.tag_name -like "v*" } }
    } catch { continue }
    $rel = $rels | Where-Object { $_.assets.name -like "raea-*-$plat.zip" } | Select-Object -First 1
    if ($rel) { $pick = @{ repo = $repo; tag = $rel.tag_name; plat = $plat }; break }
  }
  if ($pick) { break }
}
if (-not $pick) { Fail "couldn't find a release with a Windows build ($($wanted -join ' or ')) in $($repos -join ', ')." }
$tag = $pick.tag; $plat = $pick.plat
$version = $tag.TrimStart("v")
$asset = "raea-$version-$plat.zip"
$base = if ($env:RAEA_DOWNLOAD) { $env:RAEA_DOWNLOAD } else { "https://github.com/$($pick.repo)/releases/download" }
$url = "$base/$tag/$asset"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("raea-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Say "downloading raea $version ($plat) from $($pick.repo)"
  if ($machine -eq "arm64" -and $plat -eq "windows-x86_64") { Say "no ARM64 build found: installing the x86_64 one, which runs under Windows' x64 emulation" }
  try { Fetch $url (Join-Path $tmp $asset) } catch { Fail "couldn't download $url" }
  try { Fetch "$url.sha256" (Join-Path $tmp "$asset.sha256") } catch { Fail "couldn't download the checksum" }
  $want = ((Get-Content (Join-Path $tmp "$asset.sha256") -Raw).Trim() -split '\s+')[0].ToLower()
  $got = (Get-FileHash (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLower()
  if ($want -ne $got) { Fail "the download's checksum doesn't match." }
  Expand-Archive (Join-Path $tmp $asset) -DestinationPath $tmp -Force

  # replace the old install whole (a release's files go together)
  New-Item -ItemType Directory -Force -Path $prefix | Out-Null
  foreach ($d in "bin", "share") { $p = Join-Path $prefix $d; if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
  Move-Item (Join-Path $tmp "raea\bin") $prefix
  Move-Item (Join-Path $tmp "raea\share") $prefix
  Copy-Item (Join-Path $tmp "raea\README.txt") $prefix -Force
  Set-Content (Join-Path $prefix "INSTALLED.txt") "raea $version $plat from $($pick.repo), installed $(Get-Date -Format s) on a $machine machine"
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
$bin = Join-Path $prefix "bin"
$user = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not (($user -split ";") -contains $bin)) {
  [Environment]::SetEnvironmentVariable("Path", (@($bin) + ($user -split ";" | Where-Object { $_ })) -join ";", "User")
  $added = $true
}
$env:Path = "$bin;$env:Path"
Say "installed raea $version ($plat) in $prefix"

# the C runtime's DLLs come from the VC++ redistributable for the build's architecture (Microsoft's to ship, not ours)
$sys = Join-Path $env:SystemRoot "System32"
$crt = "vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll" | Where-Object { -not (Test-Path (Join-Path $sys $_)) }
if ($crt) {
  $redist = if ($plat -eq "windows-arm64") { "arm64" } else { "x64" }
  Say "raea needs the Microsoft Visual C++ Redistributable ($redist), which isn't installed ($($crt -join ', ') missing). Get it from"
  Say "  https://aka.ms/vs/17/release/vc_redist.$redist.exe"
}

if (-not $env:RAEA_NO_SKILLS) {
  $skills = Join-Path $HOME ".claude\skills"
  New-Item -ItemType Directory -Force -Path $skills | Out-Null
  foreach ($s in Get-ChildItem (Join-Path $prefix "share\raea\skills") -Directory) {
    $to = Join-Path $skills $s.Name
    if (Test-Path $to) { Remove-Item $to -Recurse -Force }
    Copy-Item $s.FullName $to -Recurse
  }
  $old = Join-Path $skills "raea-bevy"
  if (Select-String -Quiet -Pattern "^version: " -Path (Join-Path $old "SKILL.md") -ErrorAction SilentlyContinue) { Remove-Item $old -Recurse -Force }
  Say "added the raea skill to $skills"
}
if ($added) { Say "added $bin to your PATH: open a new terminal to pick it up" }
Say "try it:  raea render your-composition.tsx -o out.mp4"
