#!/bin/bash
# Quick start script for Docker

echo "AI Fitness Trainer - Docker Quick Start"
echo "=========================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "[ERROR] Docker is not installed. Please install Docker first."
    echo "   Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "[WARNING] Docker Compose not found. Using docker build/run instead..."
    USE_COMPOSE=false
else
    USE_COMPOSE=true
fi

# Check if model directory exists
if [ ! -d "Fine-Tuning/mistral-7b-squat-qlora/checkpoint-450" ]; then
    echo "[WARNING] Model directory not found!"
    echo "   The LLM feedback feature may not work without the trained model."
    echo "   Basic pose estimation will still work."
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create output directory
mkdir -p outputs

echo "Building Docker image..."
echo ""

if [ "$USE_COMPOSE" = true ]; then
    docker-compose build
    echo ""
    echo "Starting container..."
    docker-compose up
else
    docker build -t ai-fitness-trainer .
    echo ""
    echo "Starting container..."
    docker run -d \
        -p 8501:8501 \
        -v "$(pwd)/Fine-Tuning/mistral-7b-squat-qlora:/app/Fine-Tuning/mistral-7b-squat-qlora:ro" \
        -v "$(pwd)/outputs:/app/outputs" \
        --name ai-fitness-trainer \
        ai-fitness-trainer
    
    echo ""
    echo "[SUCCESS] Container started!"
    echo "Access the app at: http://localhost:8501"
    echo ""
    echo "To view logs: docker logs -f ai-fitness-trainer"
    echo "To stop: docker stop ai-fitness-trainer"
fi

