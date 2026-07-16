param(
  [ValidateSet("chrome", "edge", "chromium", "vivaldi", "all")]
  [string]$Browser = "all",

  [string]$AppDir = (Join-Path $env:LOCALAPPDATA "YouTubeLocalExporter"),

  [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"
$HostName = "com.dowen.youtube_local_exporter"
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
  & reg.exe delete $Target /f 2>$null | Out-Null
}

if ($RemoveFiles -and (Test-Path $AppDir)) {
  Remove-Item -Path $AppDir -Recurse -Force
}

Write-Host "Removed native host registry entries."
if ($RemoveFiles) {
  Write-Host "Removed $AppDir"
}
