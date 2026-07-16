$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Entry = Join-Path $Root "native-host\youtube_local_exporter_host.py"
$Dist = Join-Path $Root "native-host\dist"
$Build = Join-Path $Root "native-host\build"

New-Item -ItemType Directory -Force -Path $Dist, $Build | Out-Null

$PyInstallerArgs = @(
  "--onefile",
  "--clean",
  "--name", "youtube-local-exporter-host",
  "--distpath", $Dist,
  "--workpath", $Build,
  "--specpath", $Build,
  $Entry
)

if (Get-Command uv -ErrorAction SilentlyContinue) {
  & uv tool run pyinstaller @PyInstallerArgs
} else {
  python -m pip install --upgrade pyinstaller
  python -m PyInstaller @PyInstallerArgs
}

Write-Host "Built native host in $Dist"
