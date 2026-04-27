@echo off
REM pi - Development launcher script for Bun runtime (Windows)
REM Usage: pi.bat [options] [prompt]
REM   pi.bat              - Start interactive mode
REM   pi.bat "fix bug"    - Start with prompt
REM   pi.bat --no-env     - Start without API keys
REM   pi.bat --version    - Show version

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "NO_ENV="
set "ARGS="

REM Parse arguments
:parse_args
if "%~1"=="" goto :run
if "%~1"=="--no-env" (
    set "NO_ENV=1"
    shift
    goto :parse_args
)
if defined ARGS (
    set "ARGS=%ARGS% %~1"
) else (
    set "ARGS=%~1"
)
shift
goto :parse_args

:run
if defined NO_ENV (
    echo Running without API keys...
    set "ANTHROPIC_API_KEY="
    set "ANTHROPIC_OAUTH_TOKEN="
    set "OPENAI_API_KEY="
    set "GEMINI_API_KEY="
    set "GROQ_API_KEY="
    set "CEREBRAS_API_KEY="
    set "XAI_API_KEY="
    set "OPENROUTER_API_KEY="
    set "ZAI_API_KEY="
    set "MISTRAL_API_KEY="
    set "MINIMAX_API_KEY="
    set "MINIMAX_CN_API_KEY="
    set "AI_GATEWAY_API_KEY="
    set "OPENCODE_API_KEY="
    set "COPILOT_GITHUB_TOKEN="
    set "GH_TOKEN="
    set "GITHUB_TOKEN="
    set "GOOGLE_APPLICATION_CREDENTIALS="
    set "GOOGLE_CLOUD_PROJECT="
    set "GCLOUD_PROJECT="
    set "GOOGLE_CLOUD_LOCATION="
    set "AWS_PROFILE="
    set "AWS_ACCESS_KEY_ID="
    set "AWS_SECRET_ACCESS_KEY="
    set "AWS_SESSION_TOKEN="
    set "AWS_REGION="
    set "AWS_DEFAULT_REGION="
    set "AWS_BEARER_TOKEN_BEDROCK="
    set "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI="
    set "AWS_CONTAINER_CREDENTIALS_FULL_URI="
    set "AWS_WEB_IDENTITY_TOKEN_FILE="
    set "AZURE_OPENAI_API_KEY="
    set "AZURE_OPENAI_BASE_URL="
    set "AZURE_OPENAI_RESOURCE_NAME="
)

REM Check bun is available
where bun >nul 2>nul
if errorlevel 1 (
    echo Error: bun is not installed. Install from https://bun.sh
    exit /b 1
)

cd /d "%SCRIPT_DIR%"
bun packages/coding-agent/src/cli.ts %ARGS%
