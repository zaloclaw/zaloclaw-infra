#requires -version 5.1
[CmdletBinding()]
param(
    [switch]$TestInstallation
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Change to script directory
Set-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)

$ROOT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$BASH_SCRIPT = Join-Path $ROOT_DIR "zaloclaw-docker-setup.sh"

function Get-PreferredBash {
    # Only return Git Bash - don't fall back to WSL bash
    $gitBashPaths = @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles}\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"
    )
    
    foreach ($bashPath in $gitBashPaths) {
        if (Test-Path $bashPath) {
            try {
                # Verify it's actually Git Bash by checking version output
                $versionOutput = & $bashPath --version 2>$null
                if ($versionOutput -match "msys|mingw") {
                    return $bashPath
                }
            } catch {
                continue
            }
        }
    }
    
    return $null
}

function Test-DockerWSL2 {
    Write-Host "==> Checking Docker Desktop WSL 2 configuration..." -ForegroundColor Cyan
    
    # Check if Docker command is available
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Docker is not installed or not in PATH." -ForegroundColor Red
        Write-Host "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
        return $false
    }
    
    # Check if Docker daemon is running
    try {
        $dockerVersion = docker version --format json 2>$null | ConvertFrom-Json
        if (-not $dockerVersion) {
            Write-Host "ERROR: Docker Desktop is not running." -ForegroundColor Red
            Write-Host "Please start Docker Desktop and wait for it to be ready." -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "ERROR: Cannot connect to Docker daemon. Docker Desktop may not be running." -ForegroundColor Red
        Write-Host "Please start Docker Desktop and wait for it to be ready." -ForegroundColor Yellow
        return $false
    }
    
    # Check if Docker is using WSL 2
    try {
        $dockerInfo = docker info --format json 2>$null | ConvertFrom-Json
        $isWSL2 = $dockerInfo.KernelVersion -match "WSL2" -or 
                  $dockerInfo.OperatingSystem -match "Docker Desktop" -and 
                  $dockerInfo.Architecture -match "x86_64"
        
        if (-not $isWSL2) {
            Write-Host "ERROR: Docker Desktop is not using WSL 2 based engine." -ForegroundColor Red
            Write-Host "" -ForegroundColor Yellow
            Write-Host "To fix this:" -ForegroundColor Yellow
            Write-Host "1. Open Docker Desktop" -ForegroundColor Yellow
            Write-Host "2. Go to Settings (gear icon)" -ForegroundColor Yellow
            Write-Host "3. Go to 'General' tab" -ForegroundColor Yellow
            Write-Host "4. Check 'Use the WSL 2 based engine'" -ForegroundColor Yellow
            Write-Host "5. Click 'Apply & Restart'" -ForegroundColor Yellow
            Write-Host "6. Wait for Docker to restart" -ForegroundColor Yellow
            Write-Host "" -ForegroundColor Yellow
            return $false
        }
        
        Write-Host "==> Docker Desktop is properly configured with WSL 2" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "WARNING: Cannot determine Docker engine type. Proceeding with caution..." -ForegroundColor Yellow
        return $true  # Allow to proceed if we can't determine engine type
    }
}

function Test-BashAvailable {
    param([switch]$SkipTestMode)
    
    # If TestInstallation switch is used and we're not skipping test mode, simulate bash not being available
    if ($TestInstallation -and -not $SkipTestMode) {
        Write-Host "==> Test mode: Simulating bash not available" -ForegroundColor Yellow
        return $false
    }
    
    # Check specifically for Git Bash locations (reject WSL bash)
    $gitBashPaths = @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles}\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"
    )
    
    foreach ($bashPath in $gitBashPaths) {
        if (Test-Path $bashPath) {
            try {
                # Test if it's actually Git Bash by checking version output
                $versionOutput = & $bashPath --version 2>$null
                if ($versionOutput -match "msys|mingw") {
                    return $true
                }
            } catch {
                continue
            }
        }
    }
    
    return $false
}

function Install-GitBash {
    Write-Host "==> Git Bash not found. Installing Git for Windows..." -ForegroundColor Yellow
    
    # Check if we're on Windows (compatible with both Windows PowerShell and PowerShell Core)
    $isWindows = $PSVersionTable.PSVersion.Major -le 5 -or [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    
    if (-not $isWindows) {
        Write-Host "ERROR: This script is designed for Windows. Please install bash manually on your system." -ForegroundColor Red
        exit 1
    }
    
    # Install Git using winget
    Write-Host "==> Installing Git using winget..." -ForegroundColor Cyan
    try {
        & winget install --id Git.Git -e --source winget
        if ($LASTEXITCODE -ne 0) {
            throw "winget install failed with exit code $LASTEXITCODE"
        }
        Write-Host "==> Git installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to install Git via winget. Please install Git for Windows manually from: https://git-scm.com/download/win" -ForegroundColor Red
        exit 1
    }
    
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    
    # Verify installation
    if (-not (Test-BashAvailable -SkipTestMode)) {
        Write-Host "ERROR: Git Bash installation failed or bash is not in PATH." -ForegroundColor Red
        Write-Host "Please install Git for Windows manually from: https://git-scm.com/download/win" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "==> Git Bash is now available!" -ForegroundColor Green
}

function Invoke-BashScript {
    param(
        [string]$ScriptPath,
        [string]$BashPath
    )
    
    if (-not (Test-Path $ScriptPath)) {
        Write-Host "ERROR: Bash script not found: $ScriptPath" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "==> Executing bash script: $ScriptPath" -ForegroundColor Cyan
    
    try {
        # Store original environment (handle null values safely)
        $originalHome = if ($env:HOME) { $env:HOME } else { "" }
        $originalPath = $env:PATH
        $originalUser = if ($env:USER) { $env:USER } else { "" }
        $originalUsername = if ($env:USERNAME) { $env:USERNAME } else { "" }
        
        # Fix HOME path for Git Bash (convert Windows path to MSYS2 format)
        $windowsHome = [Environment]::GetFolderPath("UserProfile")
        $unixHome = $windowsHome -replace '^([A-Z]):', '/$1' -replace '\\', '/'
        $env:HOME = $unixHome.ToLower()
        
        # Set USER environment variable to avoid issues with user detection
        $userName = [Environment]::UserName
        $env:USER = $userName
        $env:USERNAME = $userName
        
        # Add Git's Unix tools to PATH to ensure commands like dirname, grep, etc. are available
        $gitRoot = Split-Path (Split-Path $BashPath -Parent) -Parent
        $gitBinPaths = @(
            "$gitRoot\usr\bin",
            "$gitRoot\bin", 
            "$gitRoot\mingw64\bin"
        )
        
        # Prepend Git paths to ensure Git's tools are used
        $env:PATH = ($gitBinPaths -join ";") + ";" + $env:PATH
        
        Write-Host "==> Setting up Git Bash environment (HOME=$($env:HOME), USER=$($env:USER))" -ForegroundColor Gray
        
        # Create a wrapper script that sets up the environment and runs the original script
        $scriptDir = Split-Path $ScriptPath -Parent
        $scriptName = Split-Path $ScriptPath -Leaf
        $unixScriptDir = $scriptDir -replace '^([A-Z]):', '/$1' -replace '\\', '/'
        $unixScriptDir = $unixScriptDir.ToLower()
        
        # Convert Git paths to Unix format for the bash script
        $gitRoot = Split-Path (Split-Path $BashPath -Parent) -Parent
        $unixBinPath = ($gitRoot + "\usr\bin") -replace '^([A-Z]):', '/$1' -replace '\\', '/'
        $unixBinPath = $unixBinPath.ToLower()
        $gitBinPath = ($gitRoot + "\bin") -replace '^([A-Z]):', '/$1' -replace '\\', '/'
        $gitBinPath = $gitBinPath.ToLower()
        
        $wrapperScript = @"
#!/bin/bash

# Disable conda auto-activation to avoid conflicts
export CONDA_AUTO_ACTIVATE_BASE=false
unset CONDA_EXE CONDA_PREFIX CONDA_PROMPT_MODIFIER CONDA_SHLVL CONDA_DEFAULT_ENV

# Set up PATH to include Git's Unix tools (use actual Git paths)
export PATH="${unixBinPath}:${gitBinPath}:/usr/bin:/bin:/usr/local/bin:`$PATH"

# Change to the script directory
cd "$unixScriptDir"

# Set umask to avoid permission issues
umask 022

# Execute the script directly with bash instead of relying on shebang
exec bash ./$scriptName "`$@"
"@
        
        $tempWrapperPath = Join-Path $env:TEMP "zaloclaw-wrapper-$(Get-Random).sh"
        [System.IO.File]::WriteAllText($tempWrapperPath, $wrapperScript, [System.Text.UTF8Encoding]::new($false))
        
        # Convert wrapper path to MSYS2 format
        $unixWrapperPath = $tempWrapperPath.Replace('\', '/') -replace '^([A-Z]):', '/$1'
        # Convert to lowercase for MSYS2 compatibility
        $unixWrapperPath = $unixWrapperPath.ToLower()
        
        Write-Host "==> Wrapper script created at: $tempWrapperPath" -ForegroundColor Gray
        Write-Host "==> Unix path: $unixWrapperPath" -ForegroundColor Gray
        
        # Execute the wrapper script with non-login shell to avoid profile conflicts
        & $BashPath --noprofile --norc $unixWrapperPath @args
        $exitCode = $LASTEXITCODE
        
        # Clean up wrapper script
        Remove-Item $tempWrapperPath -Force -ErrorAction SilentlyContinue
        
        # Restore original environment (handle empty values safely)
        if ($originalHome) { $env:HOME = $originalHome } else { Remove-Item env:HOME -ErrorAction SilentlyContinue }
        $env:PATH = $originalPath
        if ($originalUser) { $env:USER = $originalUser } else { Remove-Item env:USER -ErrorAction SilentlyContinue }
        if ($originalUsername) { $env:USERNAME = $originalUsername } else { Remove-Item env:USERNAME -ErrorAction SilentlyContinue }
        
        if ($exitCode -ne 0) {
            Write-Host "ERROR: Bash script failed with exit code $exitCode" -ForegroundColor Red
            exit $exitCode
        } else {
            Write-Host "==> Bash script completed successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "ERROR: Failed to execute bash script" -ForegroundColor Red
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Main execution
Write-Host "==> PowerShell Wrapper for zaloclaw-docker-setup.sh" -ForegroundColor Cyan
Write-Host "==> This script will ensure bash is available and run the original bash script" -ForegroundColor Cyan

# Check if the bash script exists
if (-not (Test-Path $BASH_SCRIPT)) {
    Write-Host "ERROR: Original bash script not found: $BASH_SCRIPT" -ForegroundColor Red
    exit 1
}

# Check Docker Desktop WSL 2 configuration
if (-not (Test-DockerWSL2)) {
    Write-Host "ERROR: Docker Desktop WSL 2 configuration check failed." -ForegroundColor Red
    exit 1
}

# Check if bash is available
$bashPath = Get-PreferredBash
if ($bashPath -and (Test-BashAvailable)) {
    Write-Host "==> Bash is available" -ForegroundColor Green
    $bashVersion = & $bashPath --version | Select-Object -First 1
    Write-Host "==> Bash version: $bashVersion" -ForegroundColor Gray
    Write-Host "==> Using bash from: $bashPath" -ForegroundColor Gray
} else {
    Write-Host "==> Bash not found, installing Git Bash..." -ForegroundColor Yellow
    Install-GitBash
    $bashPath = Get-PreferredBash
}

# Execute the original bash script
Invoke-BashScript -ScriptPath $BASH_SCRIPT -BashPath $bashPath

Write-Host "==> PowerShell wrapper completed successfully!" -ForegroundColor Green