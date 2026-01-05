@echo off
REM Quick start script for Docker (Windows)

echo AI Fitness Trainer - Docker Quick Start
echo ==========================================
echo.

REM Check if Docker is installed
where docker >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker is not installed. Please install Docker Desktop first.
    echo    Visit: https://docs.docker.com/get-docker/
    pause
    exit /b 1
)

REM Check if Docker Compose is installed
where docker-compose >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Docker Compose not found. Using docker build/run instead...
    set USE_COMPOSE=false
) else (
    set USE_COMPOSE=true
)

REM Check if model directory exists
if not exist "Fine-Tuning\mistral-7b-squat-qlora\checkpoint-450" (
    echo [WARNING] Model directory not found!
    echo    The LLM feedback feature may not work without the trained model.
    echo    Basic pose estimation will still work.
    echo.
    set /p CONTINUE="Continue anyway? (y/n) "
    if /i not "%CONTINUE%"=="y" exit /b 1
)

REM Create output directory
if not exist "outputs" mkdir outputs

echo Building Docker image...
echo.

if "%USE_COMPOSE%"=="true" (
    docker-compose build
    echo.
    echo Starting container...
    docker-compose up
) else (
    docker build -t ai-fitness-trainer .
    echo.
    echo Starting container...
    docker run -d ^
        -p 8501:8501 ^
        -v "%CD%\Fine-Tuning\mistral-7b-squat-qlora:/app/Fine-Tuning/mistral-7b-squat-qlora:ro" ^
        -v "%CD%\outputs:/app/outputs" ^
        --name ai-fitness-trainer ^
        ai-fitness-trainer
    
    echo.
    echo [SUCCESS] Container started!
    echo Access the app at: http://localhost:8501
    echo.
    echo To view logs: docker logs -f ai-fitness-trainer
    echo To stop: docker stop ai-fitness-trainer
)

pause

