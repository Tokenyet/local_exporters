[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

foreach ($Product in @("twitch", "youtube")) {
  $AppRoot = Join-Path $Root "apps\$Product"
  Write-Host "== Testing $Product =="
  Push-Location $AppRoot
  try {
    node --check src\background.js
    node --check src\content.js
    node --check popup\popup.js
    node --check options\options.js
    node scripts\smoke-test.mjs
    python -m unittest discover -s native-host\tests -p "test*.py"
  } finally {
    Pop-Location
  }
}

Write-Host "All extension tests passed."
