[CmdletBinding()]
param(
  [ValidateSet("Shared", "Isolated", "Custom")]
  [string]$ToolchainMode = "Shared",
  [string]$ToolchainRoot = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ProductKey = "twitch"
$SharedStateDir = Join-Path $env:LOCALAPPDATA "com.dowen.local_exporter"
$DefaultSharedRoot = Join-Path $SharedStateDir "toolchain"
$LegacyToolsRoot = Join-Path (Join-Path $env:LOCALAPPDATA "TwitchLocalExporter") "tools"
$SettingsPath = Join-Path $SharedStateDir "settings.json"

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

$ToolchainRoot = $ResolvedToolchainRoot
$Venv = Join-Path $ToolchainRoot "runtimes\\faster-whisper"
$Python = Join-Path $Venv "Scripts\\python.exe"
$ModelDir = Join-Path $ToolchainRoot "models\\faster-whisper"

New-Item -ItemType Directory -Force -Path $SharedStateDir, $ToolchainRoot, $ModelDir | Out-Null

$Settings = [ordered]@{
  schemaVersion = 1
  root = $DefaultSharedRoot
  products = [ordered]@{}
}
if (Test-Path $SettingsPath) {
  try {
    $existing = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json
    if ($existing.root) { $Settings.root = [string]$existing.root }
    foreach ($property in @($existing.products.PSObject.Properties)) {
      $Settings.products[$property.Name] = [ordered]@{
        mode = [string]$property.Value.mode
        root = [string]$property.Value.root
      }
    }
  } catch {
    Write-Warning "Could not read existing toolchain settings; rebuilding them."
  }
}
$Settings.products[$ProductKey] = [ordered]@{
  mode = $ToolchainMode.ToLowerInvariant()
  root = (Resolve-Path -LiteralPath $ToolchainRoot).Path
}
$Settings | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $SettingsPath

if (-not (Test-Path $Python)) {
  python -m venv $Venv
}

& $Python -m pip install --upgrade pip
& $Python -m pip install -r (Join-Path $Root "requirements-gpu.txt")
& $Python -c "import ctranslate2; count=ctranslate2.get_cuda_device_count(); print('CUDA devices:', count); raise SystemExit(0 if count > 0 else 1)"

Write-Host "GPU Whisper environment ready: $Python"
Write-Host "GPU Whisper model cache: $ModelDir"
