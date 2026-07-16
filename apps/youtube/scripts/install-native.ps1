param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[a-p]{32}$")]
  [string]$ExtensionId,

  [ValidateSet("chrome", "edge", "chromium", "vivaldi", "all")]
  [string]$Browser = "all",

  [string]$AppDir = (Join-Path $env:LOCALAPPDATA "YouTubeLocalExporter")
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$HostName = "com.dowen.youtube_local_exporter"
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
if ($Browser -in @("chrome", "all")) {
  $RegistryTargets += "HKCU\Software\Google\Chrome\NativeMessagingHosts\$HostName"
}
if ($Browser -in @("edge", "all")) {
  $RegistryTargets += "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\$HostName"
}
if ($Browser -in @("chromium", "all")) {
  $RegistryTargets += "HKCU\Software\Chromium\NativeMessagingHosts\$HostName"
}
if ($Browser -in @("vivaldi", "all")) {
  $RegistryTargets += "HKCU\Software\Vivaldi\NativeMessagingHosts\$HostName"
}

foreach ($Target in $RegistryTargets) {
  & reg.exe add $Target /ve /t REG_SZ /d $ManifestPath /f | Out-Null
}

Write-Host "Installed native host manifest: $ManifestPath"
Write-Host "Host path: $HostPath"
Write-Host "Registered browsers: $($RegistryTargets -join ', ')"
