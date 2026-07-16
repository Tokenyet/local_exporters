[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

foreach ($Product in @("twitch", "youtube")) {
  $AppRoot = Join-Path $Root "apps\$Product"
  Write-Host "== Packaging $Product =="
  Push-Location $AppRoot
  try {
    & (Join-Path $AppRoot "scripts\package.ps1")
  } finally {
    Pop-Location
  }
}

Write-Host "All extension packages created under apps\<product>\dist."
