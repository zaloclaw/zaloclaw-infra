#requires -version 5.1
[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Change to script directory
Set-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Define constants
$ROOT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ENV_PATH = Join-Path $ROOT_DIR ".env.test"  # Use test env for validation

# Build a local image that extends the official OpenClaw image with
# Playwright/Chromium and gog preinstalled.
$OPENCLAW_DEFAULT_BASE_IMAGE = "ghcr.io/openclaw/openclaw:2026.3.31"
$OPENCLAW_DOCKERFILE = Join-Path $ROOT_DIR "Dockerfile.zaloclaw"
$OPENCLAW_HOME_VOLUME = "openclaw_home"

$LITELLM_SETUP_SCRIPT = Join-Path $ROOT_DIR "litellm\llm-setup.sh"
$LITELLM_CONFIG_FILE = Join-Path $ROOT_DIR "litellm\litellm-config.yaml"

function Read-EnvValue {
  param(
    [string]$Key
  )
    
  # First check environment variable
  $value = [Environment]::GetEnvironmentVariable($Key)
  if ($value) {
    return $value
  }
    
  # If .env file doesn't exist, return empty string
  if (-not (Test-Path $ENV_PATH)) {
    return ""
  }
    
  # Read from .env file
  $content = Get-Content $ENV_PATH -ErrorAction SilentlyContinue
  $line = $content | Where-Object { $_ -match "^$Key=" } | Select-Object -Last 1
    
  if ($line) {
    $value = ($line -split "=", 2)[1]
    # Remove quotes
    $value = $value.Trim('"', "'")
    return $value
  }
    
  return ""
}

$OPENCLAW_BASE_IMAGE = Read-EnvValue "OPENCLAW_IMAGE"
if (-not $OPENCLAW_BASE_IMAGE) {
  $OPENCLAW_BASE_IMAGE = $OPENCLAW_DEFAULT_BASE_IMAGE
}

$OPENCLAW_BASE_VERSION = ($OPENCLAW_BASE_IMAGE -split ":")[-1]
$OPENCLAW_IMAGE = "openclaw:$OPENCLAW_BASE_VERSION-zaloclaw"
$OPENCLAW_BOOTSTRAP_IMAGE = $OPENCLAW_BASE_IMAGE

function Test-RequiredEnv {
  $required_vars = @(
    "OPENCLAW_CONFIG_DIR",
    "OPENCLAW_WORKSPACE_DIR", 
    "LITELLM_MASTER_KEY"
  )
    
  $provider_vars = @(
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "ANTHROPIC_API_KEY",
    "OPENROUTER_API_KEY"
  )
    
  $missing_vars = @()
  $provider_present = $false
    
  foreach ($key in $required_vars) {
    $value = Read-EnvValue $key
    if (-not $value) {
      $missing_vars += $key
    }
  }
    
  foreach ($key in $provider_vars) {
    $value = Read-EnvValue $key
    if ($value) {
      $provider_present = $true
      break
    }
  }
    
  if ($missing_vars.Count -gt 0 -or -not $provider_present) {
    Write-Host "ERROR: Missing required configuration in $ENV_PATH (or exported env vars)." -ForegroundColor Red
    if ($missing_vars.Count -gt 0) {
      Write-Host "  Required variables not set: $($missing_vars -join ', ')" -ForegroundColor Red
    }
    if (-not $provider_present) {
      Write-Host "  Set at least one provider key: OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY" -ForegroundColor Red
    }
    exit 1
  }
}

Write-Host "==> Testing environment validation..." -ForegroundColor Cyan
Test-RequiredEnv
Write-Host "[OK] Environment validation passed" -ForegroundColor Green

$OPENCLAW_CONFIG_DIR = Read-EnvValue "OPENCLAW_CONFIG_DIR"
$OPENCLAW_WORKSPACE_DIR = Read-EnvValue "OPENCLAW_WORKSPACE_DIR"

$OPENCLAW_GATEWAY_PORT = Read-EnvValue "OPENCLAW_GATEWAY_PORT"
if (-not $OPENCLAW_GATEWAY_PORT) {
  $OPENCLAW_GATEWAY_PORT = "18789"
}

$OPENCLAW_REMOTE_CDP_URL = Read-EnvValue "OPENCLAW_REMOTE_CDP_URL"
if (-not $OPENCLAW_REMOTE_CDP_URL) {
  $OPENCLAW_REMOTE_CDP_URL = "http://192.168.65.254:9222"
}

Write-Host "==> Configuration loaded:" -ForegroundColor Cyan
Write-Host "  OPENCLAW_CONFIG_DIR: $OPENCLAW_CONFIG_DIR"
Write-Host "  OPENCLAW_WORKSPACE_DIR: $OPENCLAW_WORKSPACE_DIR"
Write-Host "  OPENCLAW_GATEWAY_PORT: $OPENCLAW_GATEWAY_PORT"
Write-Host "  OPENCLAW_BASE_IMAGE: $OPENCLAW_BASE_IMAGE"
Write-Host "  OPENCLAW_IMAGE: $OPENCLAW_IMAGE"

function Test-SeedOpenClawConfig {
  Write-Host "==> Testing OpenClaw config seeding..." -ForegroundColor Cyan
    
  $template_path = Join-Path $ROOT_DIR "seed_openclaw.json"
  $config_path = Join-Path $OPENCLAW_CONFIG_DIR "openclaw.json"
  $litellm_master_key = Read-EnvValue "LITELLM_MASTER_KEY"
    
  Write-Host "  Template path: $template_path (exists: $(Test-Path $template_path))"
  Write-Host "  Config path: $config_path"
  Write-Host "  LiteLLM master key: $($litellm_master_key.Substring(0, [Math]::Min(8, $litellm_master_key.Length)))..."
    
  if (-not (Test-Path $template_path)) {
    Write-Host "  WARNING: Missing template $template_path, skipping predefined config seeding." -ForegroundColor Yellow
    return
  }
    
  # Test directory creation (without actually creating)
  Write-Host "  Would create config directory: $OPENCLAW_CONFIG_DIR"
  Write-Host "  Would create workspace directory: $OPENCLAW_WORKSPACE_DIR"
    
  # Test skills copying
  $skills_src = Join-Path $ROOT_DIR "skills"
  Write-Host "  Skills source: $skills_src (exists: $(Test-Path $skills_src))"
  if (Test-Path $skills_src) {
    Write-Host "  Would copy skills to: $(Join-Path $OPENCLAW_WORKSPACE_DIR 'skills')"
  }
    
  # Test Python/Node availability
  $pythonFound = $false
  try {
    $null = & python3 --version 2>$null
    $pythonFound = $true
    Write-Host "  [OK] Python3 available"
  }
  catch {
    try {
      $null = & python --version 2>$null
      $pythonFound = $true
      Write-Host "  [OK] Python available"
    }
    catch {
      Write-Host "  [X] Python not available"
    }
  }
    
  $nodeFound = $false
  try {
    $null = & node --version 2>$null
    $nodeFound = $true
    Write-Host "  [OK] Node.js available"
  }
  catch {
    Write-Host "  [X] Node.js not available"
  }
    
  if ($pythonFound -or $nodeFound) {
    Write-Host "  [OK] Can process config template"
  }
  else {
    Write-Host "  [WARN] No Python or Node.js available for config processing"
  }
}

function Test-LiteLLMConfig {
  Write-Host "==> Testing LiteLLM config..." -ForegroundColor Cyan
    
  Write-Host "  LiteLLM setup script: $LITELLM_SETUP_SCRIPT (exists: $(Test-Path $LITELLM_SETUP_SCRIPT))"
  Write-Host "  LiteLLM config file: $LITELLM_CONFIG_FILE (exists: $(Test-Path $LITELLM_CONFIG_FILE))"
    
  if (-not (Test-Path $LITELLM_SETUP_SCRIPT)) {
    Write-Host "  [WARN] LiteLLM setup script not found" -ForegroundColor Yellow
  }
  else {
    Write-Host "  [OK] LiteLLM setup script found"
  }
}

# Run tests
Test-SeedOpenClawConfig
Test-LiteLLMConfig

if ($DryRun) {
  Write-Host "`n==> DRY RUN - Would execute the following commands:" -ForegroundColor Cyan
  Write-Host "  docker build --build-arg `"OPENCLAW_BASE_IMAGE=$OPENCLAW_BASE_IMAGE`" -t $OPENCLAW_IMAGE -f $OPENCLAW_DOCKERFILE $ROOT_DIR"
  Write-Host "  bash docker-setup.sh (with environment variables set)"
  Write-Host "  docker compose up -d --force-recreate openclaw-gateway"
  Write-Host "  docker compose exec commands for verification"
}
else {
  Write-Host "`n==> All validation tests passed! The script logic is working correctly." -ForegroundColor Green
}

Write-Host "`n==> Test completed successfully!" -ForegroundColor Green