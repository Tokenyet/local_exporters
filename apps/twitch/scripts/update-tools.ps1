param(
  [string]$AppDir = (Join-Path $env:LOCALAPPDATA "TwitchLocalExporter"),
  [ValidateSet("Shared", "Isolated", "Custom")]
  [string]$ToolchainMode = "Shared",
  [string]$ToolchainRoot = "",
  [ValidateSet("tiny", "base", "small", "medium", "large")]
  [string]$WhisperModel = "small",
  [ValidateSet("Auto", "Cpu", "Cuda")]
  [string]$WhisperAcceleration = "Auto",
  [switch]$SkipFfmpeg,
  [switch]$SkipDeno,
  [switch]$SkipTwitchDownloader,
  [switch]$SkipWhisper,
  [switch]$ForceUpdate
)

$ErrorActionPreference = "Stop"
$ProductKey = "twitch"
$SharedStateDir = Join-Path $env:LOCALAPPDATA "com.dowen.local_exporter"
$DefaultSharedRoot = Join-Path $SharedStateDir "toolchain"
$LegacyToolsDir = Join-Path $AppDir "tools"
$SettingsPath = Join-Path $SharedStateDir "settings.json"

if ($ToolchainMode -eq "Shared") {
  $ResolvedToolchainRoot = if ($ToolchainRoot) { $ToolchainRoot } else { $DefaultSharedRoot }
} elseif ($ToolchainMode -eq "Custom") {
  if (-not $ToolchainRoot) {
    throw "-ToolchainRoot is required when -ToolchainMode Custom is used."
  }
  $ResolvedToolchainRoot = $ToolchainRoot
} else {
  $ResolvedToolchainRoot = $LegacyToolsDir
}

$ToolsDir = $ResolvedToolchainRoot
$ProductToolsDir = Join-Path $ToolsDir "products\$ProductKey"
$ModelsDir = Join-Path $ToolsDir "models"
$ManifestDir = Join-Path $ToolsDir "manifests"
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("twitch-local-exporter-tools-" + [Guid]::NewGuid().ToString("N"))

function Save-ToolchainSelection {
  New-Item -ItemType Directory -Force -Path $SharedStateDir | Out-Null
  $settings = [ordered]@{
    schemaVersion = 1
    root = $DefaultSharedRoot
    products = [ordered]@{}
  }
  if (Test-Path $SettingsPath) {
    try {
      $existing = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json
      if ($existing.root) { $settings.root = [string]$existing.root }
      foreach ($property in @($existing.products.PSObject.Properties)) {
        $settings.products[$property.Name] = [ordered]@{
          mode = [string]$property.Value.mode
          root = [string]$property.Value.root
        }
      }
    } catch {
      Write-Warning "Could not read existing toolchain settings; rebuilding them."
    }
  }
  $settings.products[$ProductKey] = [ordered]@{
    mode = $ToolchainMode.ToLowerInvariant()
    root = (Resolve-Path -LiteralPath $ResolvedToolchainRoot).Path
  }
  $settings | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $SettingsPath
}

function Import-LegacyFile {
  param([string]$RelativePath, [string]$DestinationRoot = $ToolsDir)
  $source = Join-Path $LegacyToolsDir $RelativePath
  $destination = Join-Path $DestinationRoot $RelativePath
  if ((Test-Path $source) -and (-not (Test-Path $destination))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Host "Reused legacy tool: $source"
  }
}

New-Item -ItemType Directory -Force -Path $ToolsDir, $ProductToolsDir, $ModelsDir, $ManifestDir, $TempDir | Out-Null
Save-ToolchainSelection

if ($ToolchainMode -ne "Isolated") {
  foreach ($commonFile in @("yt-dlp.exe", "deno.exe", "ffmpeg.exe", "ffprobe.exe", "whisper-cli.exe")) {
    Import-LegacyFile $commonFile
  }
  foreach ($legacyDll in Get-ChildItem -Path $LegacyToolsDir -Filter "*.dll" -File -ErrorAction SilentlyContinue) {
    Import-LegacyFile $legacyDll.Name
  }
  Import-LegacyFile "TwitchDownloaderCLI.exe" $ProductToolsDir
  Import-LegacyFile "models\ggml-$WhisperModel.bin"
}

function Download-File {
  param([string]$Url, [string]$Destination)
  $Partial = "$Destination.download"
  Write-Host "Downloading $Url"
  Invoke-WithRetry -Action "download $Url" -Script {
    if (Test-Path -LiteralPath $Partial) {
      Remove-Item -LiteralPath $Partial -Force
    }
    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($Curl) {
      & $Curl.Source --fail --location --retry 3 --retry-all-errors --connect-timeout 30 --output $Partial $Url
      if ($LASTEXITCODE -ne 0) {
        throw "curl failed with exit code $LASTEXITCODE"
      }
    } else {
      Invoke-WebRequest -Uri $Url -OutFile $Partial -UseBasicParsing | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Partial) -or (Get-Item -LiteralPath $Partial).Length -le 0) {
      throw "Downloaded file is empty: $Url"
    }
    Move-Item -LiteralPath $Partial -Destination $Destination -Force
  }
}

function Invoke-WithRetry {
  param(
    [scriptblock]$Script,
    [string]$Action,
    [int]$Attempts = 3
  )

  for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
    try {
      return & $Script
    } catch {
      if ($Attempt -ge $Attempts) {
        throw
      }
      Write-Warning "$Action failed on attempt $Attempt of $Attempts. Retrying..."
      Start-Sleep -Seconds (2 * $Attempt)
    }
  }
}

function Read-ToolVersion {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @("--version")
  )
  if (-not (Test-Path $FilePath)) {
    return ""
  }

  try {
    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FilePath
    $StartInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join " "
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true

    $Process = [System.Diagnostics.Process]::Start($StartInfo)
    if (-not $Process.WaitForExit(10000)) {
      $Process.Kill()
      return ""
    }
    if ($Process.ExitCode -ne 0) {
      return ""
    }

    $Output = $Process.StandardOutput.ReadToEnd()
    if (-not $Output) {
      $Output = $Process.StandardError.ReadToEnd()
    }
    return ($Output -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
  } catch {
    return ""
  }
}

function ConvertTo-CommandLineArgument {
  param([string]$Value)
  if ($Value -notmatch '[\s"]') {
    return $Value
  }
  $Escaped = $Value -replace '"', '\"'
  return '"' + $Escaped + '"'
}

function Find-WorkingExternalTool {
  param(
    [string]$Executable,
    [string[]]$Arguments = @("--version")
  )

  $Command = Get-Command $Executable -CommandType Application -ErrorAction SilentlyContinue
  if (-not $Command) {
    return ""
  }

  $Version = Read-ToolVersion $Command.Source $Arguments
  if (-not $Version -and ($Arguments -join " ") -ne "--help") {
    $Version = Read-ToolVersion $Command.Source @("--help")
  }
  if ($Version) {
    Write-Host "Using working PATH tool: $Executable ($Version)"
    return $Command.Source
  }

  Write-Warning "Ignoring PATH tool because it failed its probe: $($Command.Source)"
  return ""
}

function Test-WhisperCuda {
  param([string]$FilePath)
  try {
    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FilePath
    $StartInfo.Arguments = "--help"
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Process = [System.Diagnostics.Process]::Start($StartInfo)
    if (-not $Process.WaitForExit(10000)) {
      $Process.Kill()
      return $false
    }
    $Output = "$($Process.StandardOutput.ReadToEnd())`n$($Process.StandardError.ReadToEnd())"
    return $Process.ExitCode -eq 0 -and $Output -match "(?i)CUDA backend|CUDA devices"
  } catch {
    return $false
  }
}

try {
  $YtDlpPath = Join-Path $ToolsDir "yt-dlp.exe"
  if ($ForceUpdate) {
    Download-File "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" $YtDlpPath
  } elseif (Test-Path $YtDlpPath) {
    Write-Host "Reusing existing yt-dlp: $YtDlpPath"
  } else {
    $YtDlpPath = Find-WorkingExternalTool "yt-dlp.exe"
    if (-not $YtDlpPath) {
      $YtDlpPath = Join-Path $ToolsDir "yt-dlp.exe"
      Download-File "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" $YtDlpPath
    }
  }

  if (-not $SkipTwitchDownloader) {
    $TwitchDownloaderPath = Join-Path $ProductToolsDir "TwitchDownloaderCLI.exe"
    if ($ForceUpdate) {
      $TwitchDownloaderPath = Join-Path $ProductToolsDir "TwitchDownloaderCLI.exe"
    } elseif (Test-Path $TwitchDownloaderPath) {
      Write-Host "Reusing existing TwitchDownloaderCLI: $TwitchDownloaderPath"
    } else {
      $TwitchDownloaderPath = Find-WorkingExternalTool "TwitchDownloaderCLI.exe"
    }
    if ($ForceUpdate -or -not $TwitchDownloaderPath) {
      $TwitchDownloaderPath = Join-Path $ProductToolsDir "TwitchDownloaderCLI.exe"
      $Release = Invoke-WithRetry -Action "fetch TwitchDownloader release metadata" -Script {
        Invoke-RestMethod -Uri "https://api.github.com/repos/lay295/TwitchDownloader/releases/latest" -Headers @{ "User-Agent" = "twitch-local-exporter" }
      }
      $Asset = $Release.assets |
        Where-Object { $_.name -match "(?i)^TwitchDownloaderCLI-.*-Windows-x64\.zip$" } |
        Select-Object -First 1
      if (-not $Asset) {
        throw "Could not find a Windows x64 TwitchDownloaderCLI release asset."
      }
      $TwitchDownloaderZip = Join-Path $TempDir $Asset.name
      Download-File $Asset.browser_download_url $TwitchDownloaderZip
      $TwitchDownloaderExtract = Join-Path $TempDir "twitch-downloader"
      Expand-Archive -Path $TwitchDownloaderZip -DestinationPath $TwitchDownloaderExtract -Force
      $TwitchDownloaderExe = Get-ChildItem -Path $TwitchDownloaderExtract -Recurse -Filter TwitchDownloaderCLI.exe | Select-Object -First 1
      if (-not $TwitchDownloaderExe) {
        throw "Downloaded TwitchDownloaderCLI archive did not contain TwitchDownloaderCLI.exe"
      }
      Get-ChildItem -Path $TwitchDownloaderExe.Directory.FullName -File |
        Copy-Item -Destination $ProductToolsDir -Force
    }
  }

  if (-not $SkipDeno) {
    $DenoPath = Join-Path $ToolsDir "deno.exe"
    if ($ForceUpdate) {
      $DenoZip = Join-Path $TempDir "deno.zip"
      Download-File "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" $DenoZip
      $DenoExtract = Join-Path $TempDir "deno"
      Expand-Archive -Path $DenoZip -DestinationPath $DenoExtract -Force
      $DenoExe = Get-ChildItem -Path $DenoExtract -Recurse -Filter deno.exe | Select-Object -First 1
      if (-not $DenoExe) {
        throw "Downloaded Deno archive did not contain deno.exe"
      }
      Copy-Item $DenoExe.FullName $DenoPath -Force
    } elseif (Test-Path $DenoPath) {
      Write-Host "Reusing existing Deno: $DenoPath"
    } else {
      $DenoPath = Find-WorkingExternalTool "deno.exe"
      if (-not $DenoPath) {
        $DenoPath = Join-Path $ToolsDir "deno.exe"
        $DenoZip = Join-Path $TempDir "deno.zip"
        Download-File "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" $DenoZip
        $DenoExtract = Join-Path $TempDir "deno"
        Expand-Archive -Path $DenoZip -DestinationPath $DenoExtract -Force
        $DenoExe = Get-ChildItem -Path $DenoExtract -Recurse -Filter deno.exe | Select-Object -First 1
        if (-not $DenoExe) {
          throw "Downloaded Deno archive did not contain deno.exe"
        }
        Copy-Item $DenoExe.FullName $DenoPath -Force
      }
    }
  }

  if (-not $SkipFfmpeg) {
    $FfmpegPath = Join-Path $ToolsDir "ffmpeg.exe"
    $FfprobePath = Join-Path $ToolsDir "ffprobe.exe"
    if ($ForceUpdate) {
      $FfmpegZip = Join-Path $TempDir "ffmpeg.zip"
      Download-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $FfmpegZip
      $FfmpegExtract = Join-Path $TempDir "ffmpeg"
      Expand-Archive -Path $FfmpegZip -DestinationPath $FfmpegExtract -Force
      $FfmpegExe = Get-ChildItem -Path $FfmpegExtract -Recurse -Filter ffmpeg.exe | Select-Object -First 1
      $FfprobeExe = Get-ChildItem -Path $FfmpegExtract -Recurse -Filter ffprobe.exe | Select-Object -First 1
      if (-not $FfmpegExe -or -not $FfprobeExe) {
        throw "Downloaded ffmpeg archive did not contain ffmpeg.exe and ffprobe.exe"
      }
      Copy-Item $FfmpegExe.FullName $FfmpegPath -Force
      Copy-Item $FfprobeExe.FullName $FfprobePath -Force
    } elseif ((Test-Path $FfmpegPath) -and (Test-Path $FfprobePath)) {
      Write-Host "Reusing existing FFmpeg: $FfmpegPath"
    } else {
      $ExternalFfmpeg = Find-WorkingExternalTool "ffmpeg.exe" @("-version")
      $ExternalFfprobe = Find-WorkingExternalTool "ffprobe.exe" @("-version")
      if (-not $ExternalFfmpeg -or -not $ExternalFfprobe) {
        $FfmpegZip = Join-Path $TempDir "ffmpeg.zip"
        Download-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $FfmpegZip
        $FfmpegExtract = Join-Path $TempDir "ffmpeg"
        Expand-Archive -Path $FfmpegZip -DestinationPath $FfmpegExtract -Force
        $FfmpegExe = Get-ChildItem -Path $FfmpegExtract -Recurse -Filter ffmpeg.exe | Select-Object -First 1
        $FfprobeExe = Get-ChildItem -Path $FfmpegExtract -Recurse -Filter ffprobe.exe | Select-Object -First 1
        if (-not $FfmpegExe -or -not $FfprobeExe) {
          throw "Downloaded ffmpeg archive did not contain ffmpeg.exe and ffprobe.exe"
        }
        Copy-Item $FfmpegExe.FullName $FfmpegPath -Force
        Copy-Item $FfprobeExe.FullName $FfprobePath -Force
      }
    }
  }

  if (-not $SkipWhisper) {
    $WhisperPath = Join-Path $ToolsDir "whisper-cli.exe"
    if ($ForceUpdate) {
      $Release = Invoke-WithRetry -Action "fetch whisper.cpp release metadata" -Script {
        Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/whisper.cpp/releases/latest" -Headers @{ "User-Agent" = "twitch-local-exporter" }
      }
      $Asset = $Release.assets | Where-Object { $_.name -eq "whisper-bin-x64.zip" } | Select-Object -First 1
      if ($Asset) {
        $WhisperZip = Join-Path $TempDir $Asset.name
        Download-File $Asset.browser_download_url $WhisperZip
        $WhisperExtract = Join-Path $TempDir "whisper"
        Expand-Archive -Path $WhisperZip -DestinationPath $WhisperExtract -Force
        $WhisperExe = Get-ChildItem -Path $WhisperExtract -Recurse -Filter whisper-cli.exe | Select-Object -First 1
        if ($WhisperExe) {
          Copy-Item $WhisperExe.FullName $WhisperPath -Force
          Get-ChildItem -Path $WhisperExe.Directory.FullName -Filter *.dll | Copy-Item -Destination $ToolsDir -Force
        } else {
          Write-Warning "Could not find whisper-cli.exe in $($Asset.name)"
        }
      } else {
        Write-Warning "Could not find a Windows x64 whisper.cpp release asset."
      }
    } elseif (Test-Path $WhisperPath) {
      Write-Host "Reusing existing whisper.cpp: $WhisperPath"
    } else {
      $WhisperPath = Find-WorkingExternalTool "whisper-cli.exe"
      if (-not $WhisperPath) {
        $WhisperPath = Join-Path $ToolsDir "whisper-cli.exe"
        $Release = Invoke-WithRetry -Action "fetch whisper.cpp release metadata" -Script {
          Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/whisper.cpp/releases/latest" -Headers @{ "User-Agent" = "twitch-local-exporter" }
        }
        $Asset = $Release.assets | Where-Object { $_.name -eq "whisper-bin-x64.zip" } | Select-Object -First 1
        if (-not $Asset) {
          throw "Could not find a Windows x64 whisper.cpp release asset."
        }
        $WhisperZip = Join-Path $TempDir $Asset.name
        Download-File $Asset.browser_download_url $WhisperZip
        $WhisperExtract = Join-Path $TempDir "whisper"
        Expand-Archive -Path $WhisperZip -DestinationPath $WhisperExtract -Force
        $WhisperExe = Get-ChildItem -Path $WhisperExtract -Recurse -Filter whisper-cli.exe | Select-Object -First 1
        if (-not $WhisperExe) {
          throw "Downloaded whisper.cpp archive did not contain whisper-cli.exe"
        }
        Copy-Item $WhisperExe.FullName $WhisperPath -Force
        Get-ChildItem -Path $WhisperExe.Directory.FullName -Filter *.dll | Copy-Item -Destination $ToolsDir -Force
      }
    }

    $CudaCommand = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    $WantCuda = $WhisperAcceleration -eq "Cuda" -or ($WhisperAcceleration -eq "Auto" -and $CudaCommand)
    $CudaDir = Join-Path $ToolsDir "cuda"
    $CudaWhisperPath = Join-Path $CudaDir "whisper-cli.exe"
    $ExternalWhisperCuda = $false
    if ($WhisperPath -and -not (Test-Path $WhisperPath)) {
      $ExternalWhisperCuda = Test-WhisperCuda $WhisperPath
    }
    if ($WantCuda -and ($ForceUpdate -or (-not $ExternalWhisperCuda -and -not (Test-Path $CudaWhisperPath)))) {
      if (-not $Release) {
        $Release = Invoke-WithRetry -Action "fetch whisper.cpp release metadata" -Script {
          Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/whisper.cpp/releases/latest" -Headers @{ "User-Agent" = "twitch-local-exporter" }
        }
      }
      $CudaAsset = $Release.assets |
        ForEach-Object {
          $Match = [regex]::Match($_.name, "^whisper-cublas-(\d+\.\d+\.\d+)-bin-x64\.zip$")
          if ($Match.Success) {
            [PSCustomObject]@{ Asset = $_; Version = [version]$Match.Groups[1].Value }
          }
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1
      if (-not $CudaAsset) {
        Write-Warning "Could not find a Windows x64 CUDA whisper.cpp release asset; keeping CPU Whisper."
      } else {
        New-Item -ItemType Directory -Force -Path $CudaDir | Out-Null
        $CudaZip = Join-Path $TempDir $CudaAsset.Asset.name
        Download-File $CudaAsset.Asset.browser_download_url $CudaZip
        $CudaExtract = Join-Path $TempDir "whisper-cuda"
        Expand-Archive -Path $CudaZip -DestinationPath $CudaExtract -Force
        $CudaWhisperExe = Get-ChildItem -Path $CudaExtract -Recurse -Filter whisper-cli.exe | Select-Object -First 1
        if (-not $CudaWhisperExe) {
          throw "Downloaded CUDA whisper.cpp archive did not contain whisper-cli.exe"
        }
        Get-ChildItem -Path $CudaWhisperExe.Directory.FullName -File |
          Copy-Item -Destination $CudaDir -Force
        Write-Host "Installed CUDA Whisper: $CudaWhisperPath"
      }
    } elseif ($WantCuda -and $ExternalWhisperCuda) {
      Write-Host "Using PATH CUDA Whisper: $WhisperPath"
    } elseif ($WantCuda -and (Test-Path $CudaWhisperPath)) {
      Write-Host "Reusing CUDA Whisper: $CudaWhisperPath"
    }

    $ModelPath = Join-Path $ModelsDir "ggml-$WhisperModel.bin"
    if (-not (Test-Path $ModelPath)) {
      Download-File "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$WhisperModel.bin" $ModelPath
    }
  }

  $Versions = [ordered]@{
    updatedAt = (Get-Date).ToString("o")
    product = $ProductKey
    toolchainMode = $ToolchainMode.ToLowerInvariant()
    toolchainRoot = (Resolve-Path -LiteralPath $ToolsDir).Path
    ytDlp = Read-ToolVersion (Join-Path $ToolsDir "yt-dlp.exe")
    twitchDownloaderCli = Read-ToolVersion (Join-Path $ProductToolsDir "TwitchDownloaderCLI.exe")
    ffmpeg = Read-ToolVersion (Join-Path $ToolsDir "ffmpeg.exe") @("-version")
    deno = Read-ToolVersion (Join-Path $ToolsDir "deno.exe")
    whisperModel = "ggml-$WhisperModel.bin"
    whisperAcceleration = $WhisperAcceleration.ToLowerInvariant()
    whisperCudaCli = if (Test-Path (Join-Path $ToolsDir "cuda\whisper-cli.exe")) { "cuda\whisper-cli.exe" } else { "" }
  }
  $Versions | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path (Join-Path $ManifestDir "$ProductKey.json")
  Write-Host "Tools installed in $ToolsDir"
} finally {
  if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force
  }
}
