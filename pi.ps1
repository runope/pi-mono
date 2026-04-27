# pi - Development launcher script for Bun runtime (PowerShell)
# Usage: .\pi.ps1 [options] [prompt]
#   .\pi.ps1              - Start interactive mode
#   .\pi.ps1 "fix bug"    - Start with prompt
#   .\pi.ps1 -NoEnv       - Start without API keys
#   .\pi.ps1 -Version     - Show version

param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arguments,
    
    [switch]$NoEnv,
    [switch]$Version,
    [switch]$Help
)

$ScriptDir = $PSScriptRoot

if ($Version) {
    & bun packages/coding-agent/src/cli.ts --version
    exit 0
}

if ($Help) {
    @"
pi - Development launcher for Bun runtime

Usage: .\pi.ps1 [options] [prompt]

Options:
    -NoEnv      Start without API keys (for testing)
    -Version    Show version
    -Help       Show this help

Examples:
    .\pi.ps1              Start interactive mode
    .\pi.ps1 "fix bug"    Start with prompt
    .\pi.ps1 -NoEnv       Start without API keys
"@
    exit 0
}

if ($NoEnv) {
    # Unset API keys (see packages/ai/src/env-api-keys.ts)
    $env:ANTHROPIC_API_KEY = $null
    $env:ANTHROPIC_OAUTH_TOKEN = $null
    $env:OPENAI_API_KEY = $null
    $env:GEMINI_API_KEY = $null
    $env:GROQ_API_KEY = $null
    $env:CEREBRAS_API_KEY = $null
    $env:XAI_API_KEY = $null
    $env:OPENROUTER_API_KEY = $null
    $env:ZAI_API_KEY = $null
    $env:MISTRAL_API_KEY = $null
    $env:MINIMAX_API_KEY = $null
    $env:MINIMAX_CN_API_KEY = $null
    $env:AI_GATEWAY_API_KEY = $null
    $env:OPENCODE_API_KEY = $null
    $env:COPILOT_GITHUB_TOKEN = $null
    $env:GH_TOKEN = $null
    $env:GITHUB_TOKEN = $null
    $env:GOOGLE_APPLICATION_CREDENTIALS = $null
    $env:GOOGLE_CLOUD_PROJECT = $null
    $env:GCLOUD_PROJECT = $null
    $env:GOOGLE_CLOUD_LOCATION = $null
    $env:AWS_PROFILE = $null
    $env:AWS_ACCESS_KEY_ID = $null
    $env:AWS_SECRET_ACCESS_KEY = $null
    $env:AWS_SESSION_TOKEN = $null
    $env:AWS_REGION = $null
    $env:AWS_DEFAULT_REGION = $null
    $env:AWS_BEARER_TOKEN_BEDROCK = $null
    $env:AWS_CONTAINER_CREDENTIALS_RELATIVE_URI = $null
    $env:AWS_CONTAINER_CREDENTIALS_FULL_URI = $null
    $env:AWS_WEB_IDENTITY_TOKEN_FILE = $null
    $env:AZURE_OPENAI_API_KEY = $null
    $env:AZURE_OPENAI_BASE_URL = $null
    $env:AZURE_OPENAI_RESOURCE_NAME = $null
    Write-Host "Running without API keys..."
}

# Check bun is available
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Error "Error: bun is not installed. Install from https://bun.sh"
    exit 1
}

Set-Location $ScriptDir
& bun packages/coding-agent/src/cli.ts @Arguments
