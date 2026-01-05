# Docker Setup Guide

This guide explains how to run the AI Fitness Trainer using Docker.

## Prerequisites

- Docker installed on your system ([Install Docker](https://docs.docker.com/get-docker/))
- Docker Compose (usually included with Docker Desktop)
- At least 8GB of RAM (16GB recommended for LLM features)
- For GPU support: NVIDIA Docker runtime ([nvidia-docker2](https://github.com/NVIDIA/nvidia-docker))

## Quick Start

### Option 1: Using Docker Compose (Recommended)

1. **Clone or download this repository**
   ```bash
   git clone <repository-url>
   cd ai-fitness-trainer-using-mediapipe
   ```

2. **Build and run the container**
   ```bash
   docker-compose up --build
   ```

3. **Access the application**
   - Open your browser and go to: `http://localhost:8501`
   - The Streamlit app should be running

4. **Stop the container**
   ```bash
   docker-compose down
   ```

### Option 2: Using Docker directly

1. **Build the Docker image**
   ```bash
   docker build -t ai-fitness-trainer .
   ```

2. **Run the container**
   ```bash
   docker run -d \
     -p 8501:8501 \
     -v $(pwd)/Fine-Tuning/mistral-7b-squat-qlora:/app/Fine-Tuning/mistral-7b-squat-qlora:ro \
     -v $(pwd)/outputs:/app/outputs \
     --name ai-fitness-trainer \
     ai-fitness-trainer
   ```

3. **Access the application**
   - Open your browser and go to: `http://localhost:8501`

4. **View logs**
   ```bash
   docker logs -f ai-fitness-trainer
   ```

5. **Stop the container**
   ```bash
   docker stop ai-fitness-trainer
   docker rm ai-fitness-trainer
   ```

## GPU Support (Optional)

If you have an NVIDIA GPU and want to use it for faster LLM inference:

1. **Install NVIDIA Docker runtime**
   ```bash
   # Ubuntu/Debian
   distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
   curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
   sudo apt-get update && sudo apt-get install -y nvidia-docker2
   sudo systemctl restart docker
   ```

2. **Uncomment GPU section in docker-compose.yml**
   ```yaml
   deploy:
     resources:
       reservations:
         devices:
           - driver: nvidia
             count: 1
             capabilities: [gpu]
   ```

3. **Rebuild and run**
   ```bash
   docker-compose up --build
   ```

## Volume Mounts

The Docker setup includes several volume mounts:

- **Model files**: `./Fine-Tuning/mistral-7b-squat-qlora` - Read-only mount for the fine-tuned model
- **Output videos**: `./outputs` - Directory for processed output videos
- **Input videos** (optional): `./videos` - Directory for input videos to process

## Running the Demo Script

To run the standalone demo script (without Streamlit):

```bash
docker run -it --rm \
  -v $(pwd)/Fine-Tuning/mistral-7b-squat-qlora:/app/Fine-Tuning/mistral-7b-squat-qlora:ro \
  --device=/dev/video0 \
  ai-fitness-trainer \
  python demo.py
```

**Note**: Webcam access requires `--device=/dev/video0` (Linux) or proper device mapping for your OS.

## Troubleshooting

### Port Already in Use
If port 8501 is already in use, change it in `docker-compose.yml`:
```yaml
ports:
  - "8502:8501"  # Use port 8502 on host
```

### Out of Memory
If you encounter memory issues:
- Increase Docker's memory limit in Docker Desktop settings
- Disable LLM features if not needed
- Use CPU-only mode (GPU requires more memory)

### Model Files Not Found
Ensure the model directory exists:
```bash
ls -la Fine-Tuning/mistral-7b-squat-qlora/checkpoint-450/
```

If the model files are missing, you'll need to train the model first or download the pre-trained weights.

### Webcam Not Working
For webcam access in Docker:
- Linux: Use `--device=/dev/video0`
- Windows/Mac: Webcam access in Docker containers is limited; consider using the Streamlit web interface with WebRTC

## Building for Production

For production deployment, you may want to:

1. **Use a specific Python version**
   ```dockerfile
   FROM python:3.10-slim
   ```

2. **Optimize image size**
   - Use multi-stage builds
   - Remove unnecessary dependencies
   - Use `.dockerignore` effectively

3. **Add environment variables**
   ```yaml
   environment:
     - MODEL_PATH=/app/Fine-Tuning/mistral-7b-squat-qlora
     - LOG_LEVEL=INFO
   ```

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Streamlit Documentation](https://docs.streamlit.io/)
- [NVIDIA Docker Documentation](https://github.com/NVIDIA/nvidia-docker)

## Support

For issues or questions, please check the main README.md or open an issue on the repository.

