param(
  [string]$ExtensionId = "",

  [ValidateSet("chrome", "edge", "chromium", "vivaldi", "all")]
  [string]$Browser = "all",

  [ValidateSet("Shared", "Isolated", "Custom")]
  [string]$ToolchainMode = "Shared",

  [string]$ToolchainRoot = "",

  [string]$AppDir = (Join-Path $env:LOCALAPPDATA "YouTubeLocalExporter")
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Manifest = Get-Content -LiteralPath (Join-Path $Root "manifest.json") -Raw | ConvertFrom-Json
if (-not $ExtensionId) {
  if ([string]::IsNullOrWhiteSpace($Manifest.key)) {
    throw "Manifest has no stable public signing key. Pass -ExtensionId explicitly."
  }
  $PublicKey = [Convert]::FromBase64String($Manifest.key)
  $Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($PublicKey)
  $ExtensionId = -join ($Hash[0..15] | ForEach-Object {
    [char](97 + (($_ -shr 4) -band 15))
    [char](97 + ($_ -band 15))
  })
}
if ($ExtensionId -notmatch "^[a-p]{32}$") {
  throw "ExtensionId must be 32 lowercase characters in the a-p range: $ExtensionId"
}
$HostName = "com.dowen.youtube_local_exporter"
$ProductKey = "youtube"
Write-Host "Using stable YouTube extension ID: $ExtensionId"
$SharedStateDir = Join-Path $env:LOCALAPPDATA "com.dowen.local_exporter"
$DefaultSharedRoot = Join-Path $SharedStateDir "toolchain"
$SettingsPath = Join-Path $SharedStateDir "settings.json"
$LegacyToolsRoot = Join-Path $AppDir "tools"

if ($ToolchainMode -eq "Shared") {
  $ResolvedToolchainRoot = if ($ToolchainRoot) { $ToolchainRoot } else { $DefaultSharedRoot }
} elseif ($ToolchainMode -eq "Custom") {
  if (-not $ToolchainRoot) {
    throw "-ToolchainRoot is required when -ToolchainMode Custom is used."
  }
  $ResolvedToolchainRoot = $ToolchainRoot
} else {
  $ResolvedToolchainRoot = $LegacyToolsRoot
}

$Settings = [ordered]@{
  schemaVersion = 1
  root = $DefaultSharedRoot
  products = [ordered]@{}
}
if (Test-Path $SettingsPath) {
  try {
    $ExistingSettings = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json
    if ($ExistingSettings.root) { $Settings.root = [string]$ExistingSettings.root }
    foreach ($Property in @($ExistingSettings.products.PSObject.Properties)) {
      $Settings.products[$Property.Name] = [ordered]@{
        mode = [string]$Property.Value.mode
        root = [string]$Property.Value.root
      }
    }
  } catch {
    Write-Warning "Could not read existing toolchain settings; rebuilding them."
  }
}
New-Item -ItemType Directory -Force -Path $SharedStateDir, $ResolvedToolchainRoot | Out-Null
$Settings.products[$ProductKey] = [ordered]@{
  mode = $ToolchainMode.ToLowerInvariant()
  root = (Resolve-Path -LiteralPath $ResolvedToolchainRoot).Path
}
$Settings | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $SettingsPath

$NativeDest = Join-Path $AppDir "native-host"
$ScriptsDest = Join-Path $AppDir "scripts"
$ManifestPath = Join-Path $AppDir "$HostName.json"
$LauncherPath = Join-Path $AppDir "youtube-local-exporter-host.cmd"
$BuiltHost = Join-Path $Root "native-host\dist\youtube-local-exporter-host.exe"
$InstalledHost = Join-Path $AppDir "youtube-local-exporter-host.exe"

New-Item -ItemType Directory -Force -Path $NativeDest, $ScriptsDest | Out-Null
Copy-Item -Path (Join-Path $Root "native-host\*") -Destination $NativeDest -Recurse -Force
Copy-Item -Path (Join-Path $Root "scripts\update-tools.ps1") -Destination $ScriptsDest -Force

if (Test-Path $BuiltHost) {
  Copy-Item -Path $BuiltHost -Destination $InstalledHost -Force
  $HostPath = $InstalledHost
} else {
@"
@echo off
set PYTHONUTF8=1
where python >nul 2>nul
if not errorlevel 1 (
  python "%~dp0native-host\youtube_local_exporter_host.py"
  exit /b %ERRORLEVEL%
)
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0native-host\youtube_local_exporter_host.py"
  exit /b %ERRORLEVEL%
)
echo Python 3.11 or newer was not found. 1>&2
exit /b 1
"@ | Set-Content -Encoding ASCII -Path $LauncherPath
  $HostPath = $LauncherPath
}

$Manifest = [ordered]@{
  name = $HostName
  description = "YouTube Local Exporter native messaging host"
  path = $HostPath
  type = "stdio"
  allowed_origins = @("chrome-extension://$ExtensionId/")
}
$Manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $ManifestPath

$RegistryTargets = @()
# Vivaldi on Windows uses Chromium's Chrome native-messaging registry root.
if ($Browser -in @("chrome", "vivaldi", "all")) {
  $RegistryTargets += "HKCU\Software\Google\Chrome\NativeMessagingHosts\$HostName"
}
if ($Browser -in @("edge", "all")) {
  $RegistryTargets += "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\$HostName"
}
if ($Browser -in @("chromium", "all")) {
  $RegistryTargets += "HKCU\Software\Chromium\NativeMessagingHosts\$HostName"
}
foreach ($Target in $RegistryTargets) {
  & reg.exe add $Target /ve /t REG_SZ /d $ManifestPath /f | Out-Null
}

Write-Host "Installed native host manifest: $ManifestPath"
Write-Host "Host path: $HostPath"
Write-Host "Registered browsers: $($RegistryTargets -join ', ')"
