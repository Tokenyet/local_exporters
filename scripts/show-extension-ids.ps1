[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Get-ExtensionId {
  param([Parameter(Mandatory = $true)][string]$ManifestPath)

  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($Manifest.key)) {
    throw "Manifest has no stable public signing key: $ManifestPath"
  }

  $PublicKey = [Convert]::FromBase64String($Manifest.key)
  $Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($PublicKey)
  $IdChars = foreach ($Byte in $Hash[0..15]) {
    [char](97 + (($Byte -shr 4) -band 15))
    [char](97 + ($Byte -band 15))
  }

  return -join $IdChars
}

foreach ($Product in @("twitch", "youtube")) {
  $ManifestPath = Join-Path $Root "apps\$Product\manifest.json"
  $Id = Get-ExtensionId -ManifestPath $ManifestPath
  [pscustomobject]@{
    Product = $Product
    ExtensionId = $Id
  }
}
