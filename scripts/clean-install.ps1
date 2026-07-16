[CmdletBinding()]
param(
  [string]$TwitchExtensionId = "",
  [string]$YoutubeExtensionId = "",
  [ValidateSet("default", "chrome", "edge", "chromium", "vivaldi", "all")]
  [string]$Browser = "default",
  [switch]$PurgeSharedToolchain,

  [ValidateSet("tiny", "base", "small", "medium", "large")]
  [string]$WhisperModel = "small",

  [ValidateSet("Auto", "Cpu", "Cuda")]
  [string]$WhisperAcceleration = "Auto",

  [switch]$SkipUpdateTools
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Resolve-DefaultBrowser {
  $UserChoicePath = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice"
  $UserChoice = Get-ItemProperty -Path $UserChoicePath -Name ProgId -ErrorAction SilentlyContinue
  $ProgId = [string]$UserChoice.ProgId

  switch -Regex ($ProgId) {
    "^ChromeHTML" { return "chrome" }
    "^MSEdgeHTM" { return "edge" }
    "^ChromiumHTM" { return "chromium" }
    "^VivaldiHTM" { return "vivaldi" }
    default {
      throw "Could not map Windows default browser ProgId '$ProgId'. Use -Browser all or specify chrome, edge, chromium, or vivaldi."
    }
  }
}

$ResolvedBrowser = if ($Browser -eq "default") { Resolve-DefaultBrowser } else { $Browser }
Write-Host "Using browser target: $ResolvedBrowser"
$UninstallBrowser = if ($Browser -eq "default") { "all" } else { $ResolvedBrowser }

function Get-ManifestExtensionId {
  param([Parameter(Mandatory = $true)][string]$ManifestPath)
  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($Manifest.key)) {
    throw "Manifest has no stable public signing key: $ManifestPath"
  }
  $PublicKey = [Convert]::FromBase64String($Manifest.key)
  $Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($PublicKey)
  return -join ($Hash[0..15] | ForEach-Object {
    [char](97 + (($_ -shr 4) -band 15))
    [char](97 + ($_ -band 15))
  })
}

if (-not $TwitchExtensionId) {
  $TwitchExtensionId = Get-ManifestExtensionId -ManifestPath (Join-Path $Root "apps\twitch\manifest.json")
}
if (-not $YoutubeExtensionId) {
  $YoutubeExtensionId = Get-ManifestExtensionId -ManifestPath (Join-Path $Root "apps\youtube\manifest.json")
}

foreach ($Id in @($TwitchExtensionId, $YoutubeExtensionId)) {
  if ($Id -notmatch '^[a-p]{32}$') {
    throw "Extension IDs must be 32 lowercase characters in the a-p range: $Id"
  }
}

foreach ($Product in @("twitch", "youtube")) {
  $AppRoot = Join-Path $Root "apps\$Product"
  Write-Host "== Removing native installation for $Product =="
  & (Join-Path $AppRoot "scripts\uninstall-native.ps1") -Browser $UninstallBrowser
}

$InstallRoots = @(
  (Join-Path $env:LOCALAPPDATA "TwitchLocalExporter"),
  (Join-Path $env:LOCALAPPDATA "YouTubeLocalExporter")
)
foreach ($InstallRoot in $InstallRoots) {
  if (Test-Path -LiteralPath $InstallRoot) {
    $ResolvedRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
    $LocalAppDataRoot = (Resolve-Path -LiteralPath $env:LOCALAPPDATA).Path
    if (-not $ResolvedRoot.StartsWith($LocalAppDataRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove install directory outside LOCALAPPDATA: $ResolvedRoot"
    }
    Remove-Item -LiteralPath $ResolvedRoot -Recurse -Force
  }
}

if ($PurgeSharedToolchain) {
  $SharedRoot = Join-Path $env:LOCALAPPDATA "com.dowen.local_exporter"
  if (Test-Path -LiteralPath $SharedRoot) {
    $ResolvedSharedRoot = (Resolve-Path -LiteralPath $SharedRoot).Path
    $LocalAppDataRoot = (Resolve-Path -LiteralPath $env:LOCALAPPDATA).Path
    if (-not $ResolvedSharedRoot.StartsWith($LocalAppDataRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove shared toolchain outside LOCALAPPDATA: $ResolvedSharedRoot"
    }
    Remove-Item -LiteralPath $ResolvedSharedRoot -Recurse -Force
  }
}

& (Join-Path $Root "apps\twitch\scripts\install-native.ps1") -ExtensionId $TwitchExtensionId -Browser $ResolvedBrowser -ToolchainMode Shared
& (Join-Path $Root "apps\youtube\scripts\install-native.ps1") -ExtensionId $YoutubeExtensionId -Browser $ResolvedBrowser -ToolchainMode Shared

if (-not $SkipUpdateTools) {
  Write-Host "== Updating shared Twitch toolchain =="
  & (Join-Path $Root "apps\twitch\scripts\update-tools.ps1") -ToolchainMode Shared -WhisperModel $WhisperModel -WhisperAcceleration $WhisperAcceleration

  Write-Host "== Updating shared YouTube toolchain =="
  & (Join-Path $Root "apps\youtube\scripts\update-tools.ps1") -ToolchainMode Shared -WhisperModel $WhisperModel -WhisperAcceleration $WhisperAcceleration
}

Write-Host "Clean install completed. Native hosts and shared tools are ready. The manifest signing keys keep the extension IDs stable. Reload the unpacked extension directories in the browser before testing each product."
