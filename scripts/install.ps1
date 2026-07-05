# dot Windows installer
# Usage:
#   irm https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.ps1 | iex

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$VerboseInstall
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Help {
    Write-Host "dot installation script for Windows"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  irm https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.ps1 | iex"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help             Show this help message"
    Write-Host "  -VerboseInstall   Print verbose output"
    Write-Host ""
    Write-Host "This script will:"
    Write-Host "  1. Detect your OS and architecture"
    Write-Host "  2. Download the latest dot binary from GitHub"
    Write-Host "  3. Install it to %LOCALAPPDATA%\Programs\dot\dot.exe"
    Write-Host "  4. Update your user PATH"
    Write-Host ""
    Write-Host "Requirements:"
    Write-Host "  - PowerShell"
    Write-Host "  - Internet connection"
}

function Assert-Windows {
    if ($env:OS -ne "Windows_NT") {
        Write-ErrorMessage "This installer is for Windows only. Use scripts/install.sh on macOS or Linux."
        exit 1
    }
}

function Get-DotArchitecture {
    $arch = $env:PROCESSOR_ARCHITECTURE

    if (-not $arch -and $env:PROCESSOR_ARCHITEW6432) {
        $arch = $env:PROCESSOR_ARCHITEW6432
    }

    if (-not $arch) {
        Write-ErrorMessage "Could not detect Windows architecture"
        exit 1
    }

    switch ($arch.ToLowerInvariant()) {
        "amd64" { return "x64" }
        "x86_64" { return "x64" }
        "x64" { return "x64" }
        "arm64" {
            Write-ErrorMessage "Unsupported architecture: arm64"
            Write-WarningMessage "The release workflow currently publishes dot-windows-x64.exe only."
            exit 1
        }
        default {
            Write-ErrorMessage "Unsupported architecture: $arch"
            exit 1
        }
    }
}

function Get-LatestRelease {
    Write-Info "Fetching latest version..."

    $headers = @{
        "Accept" = "application/vnd.github.v3+json"
        "User-Agent" = "dot-installer"
    }

    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/pablopunk/dot/releases/latest" `
        -Headers $headers

    if (-not $release.tag_name) {
        Write-ErrorMessage "Failed to fetch latest version"
        exit 1
    }

    Write-Info "Latest version: $($release.tag_name)"
    return $release
}

function Save-DotBinary {
    param(
        [object]$Release,
        [string]$Architecture
    )

    $binaryName = "dot-windows-$Architecture.exe"
    $asset = $Release.assets | Where-Object { $_.name -eq $binaryName } | Select-Object -First 1

    if (-not $asset) {
        Write-ErrorMessage "No release asset found for $binaryName"
        exit 1
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dot-install-" + [System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $tempFile = Join-Path $tempDir "dot.exe"

    Write-Info "Downloading from: $($asset.browser_download_url)"
    Invoke-WebRequest `
        -Uri $asset.browser_download_url `
        -OutFile $tempFile `
        -UseBasicParsing

    if (-not (Test-Path $tempFile)) {
        Write-ErrorMessage "Failed to download binary"
        exit 1
    }

    Write-Success "Binary downloaded successfully"

    return @{
        TempDir = $tempDir
        TempFile = $tempFile
    }
}

function Install-DotBinary {
    param([string]$TempFile)

    $installDir = Join-Path $env:LOCALAPPDATA "Programs\dot"
    $dotPath = Join-Path $installDir "dot.exe"

    if (-not (Test-Path $installDir)) {
        Write-Info "Creating $installDir"
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    Write-Info "Installing binary to $dotPath"
    Move-Item -Path $TempFile -Destination $dotPath -Force

    Write-Success "Binary installed to $dotPath"

    return @{
        InstallDir = $installDir
        DotPath = $dotPath
    }
}

function Add-ToUserPath {
    param([string]$InstallDir)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathParts = @()
    if ($userPath) {
        $pathParts = $userPath -split ";" | Where-Object { $_ }
    }

    $normalizedInstallDir = $InstallDir.TrimEnd("\")
    $isInPath = $false

    foreach ($pathPart in $pathParts) {
        if ($pathPart.TrimEnd("\") -ieq $normalizedInstallDir) {
            $isInPath = $true
            break
        }
    }

    if ($isInPath) {
        Write-Info "$InstallDir is already in user PATH"
        return
    }

    Write-Info "Adding $InstallDir to user PATH"

    if ($userPath) {
        $newPath = "$userPath;$InstallDir"
    } else {
        $newPath = $InstallDir
    }

    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$InstallDir"

    Write-Success "Updated user PATH"
    Write-WarningMessage "Restart your terminal to use dot from new sessions"
}

function Test-Installation {
    param([string]$DotPath)

    if (-not (Test-Path $DotPath)) {
        Write-ErrorMessage "Installation failed: $DotPath does not exist"
        exit 1
    }

    Write-Success "Installation verified: $DotPath exists"

    try {
        & $DotPath --help *> $null
        Write-Success "Binary runs successfully"
    } catch {
        Write-WarningMessage "Binary exists but may not run correctly"
    }
}

function Remove-TempDir {
    param([string]$TempDir)

    if ($TempDir -and (Test-Path $TempDir)) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
}

function Main {
    if ($Help) {
        Show-Help
        return
    }

    if ($VerboseInstall) {
        Set-PSDebug -Trace 1
    }

    Write-Info "Starting dot installation..."

    $tempDir = $null

    try {
        Assert-Windows
        $architecture = Get-DotArchitecture
        Write-Info "Detected OS: windows, Architecture: $architecture"

        $release = Get-LatestRelease
        $download = Save-DotBinary -Release $release -Architecture $architecture
        $tempDir = $download.TempDir

        $installation = Install-DotBinary -TempFile $download.TempFile
        Add-ToUserPath -InstallDir $installation.InstallDir
        Test-Installation -DotPath $installation.DotPath

        Write-Success "dot installation completed successfully!"
        Write-Info "You can now use 'dot' command (restart your terminal first if needed)"
        Write-Info "For help, run: dot --help"
        Write-Info "To get started, create a dot.toml file in your dotfiles directory"
    } finally {
        Remove-TempDir -TempDir $tempDir
    }
}

Main
