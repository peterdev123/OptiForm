# AI Fitness Trainer: Squats Analysis

An AI-powered fitness application that uses computer vision (MediaPipe) and fine-tuned language models to analyze and provide feedback on back squat form in real-time.

## Quick Start with Docker (Recommended)

The easiest way to run this project is using Docker. Follow these steps:

### Step 1: Clone the Repository

```bash
git clone <your-repository-url>
cd ai-fitness-trainer-using-mediapipe
```

### Step 2: Set Up Model Files (Important!)

The fine-tuned model files are **not included** in the repository due to their size. You have two options:

**Option A: Download Pre-trained Model** (if available)
- Download the model files and place them in: `Fine-Tuning/mistral-7b-squat-qlora/checkpoint-450/`
- The LLM feedback feature requires these files

**Option B: Train Your Own Model**
- Follow instructions in `Fine-Tuning/README.md` to train the model
- This requires the training dataset and GPU resources

**Note**: The basic pose estimation (without LLM feedback) will work without model files.

### Step 3: Run with Docker Compose

```bash
docker-compose up --build
```

### Step 4: Access the Application

Open your browser and navigate to: **http://localhost:8501**

The Streamlit application will be running with:
- **Live Stream**: Real-time squat analysis using webcam
- **Upload Video**: Analyze recorded videos

### Step 5: Stop the Container

```bash
docker-compose down
```

## Prerequisites

- **Docker** and **Docker Compose** installed ([Install Docker](https://docs.docker.com/get-docker/))
- **8GB RAM minimum** (16GB recommended for LLM features)
- **GPU** (optional, but recommended for LLM inference - see GPU setup below)

## Docker Workflow for Users

### For Repository Maintainers (You):

1. **Push your code to GitHub:**
   ```bash
   git add .
   git commit -m "Add Docker support"
   git push origin main
   ```

2. **Important**: Model files are large. Consider:
   - Using **Git LFS** for model files (if you want to include them)
   - Or providing download links in the README
   - Or hosting models on cloud storage (HuggingFace, etc.)

### For Other Users (Pulling and Running):

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd ai-fitness-trainer-using-mediapipe
   ```

2. **Get model files** (if needed for LLM features):
   - Download from provided link, or
   - Train your own (see `Fine-Tuning/README.md`)

3. **Build and run:**
   ```bash
   docker-compose up --build
   ```

4. **Access at:** http://localhost:8501

That's it! Docker handles all dependencies automatically.

## Features

- **Real-time Pose Estimation**: MediaPipe-based body landmark detection
- **Form Analysis**: Analyzes squat depth, posture, heel lifting, knee position, and more
- **AI-Powered Feedback**: Personalized feedback using fine-tuned Mistral-7B model
- **Multiple Modes**: Beginner and Pro modes with different form thresholds
- **Body Type Customization**: Adapts analysis based on body proportions

## Project Structure

```
ai-fitness-trainer-using-mediapipe/
├── app.py                 # Main Streamlit entry point
├── demo.py                # Standalone demo script (no Streamlit)
├── process_frame.py       # Core pose processing and analysis
├── llm_feedback.py       # LLM feedback generation
├── utils.py               # MediaPipe utilities
├── thresholds.py          # Form analysis thresholds
├── pages/                 # Streamlit pages
│   ├── 1_Live_Stream.py
│   └── 2_Upload_Video.py
├── Fine-Tuning/           # Model training and inference
│   ├── train_qlora.py
│   ├── inference.py
│   └── mistral-7b-squat-qlora/  # Trained model (not in repo)
├── Dockerfile             # Docker image definition
├── docker-compose.yml     # Docker Compose configuration
└── requirements.txt       # Python dependencies
```

## Alternative: Local Installation (Without Docker)

If you prefer to run without Docker:

1. **Install Python 3.10+**

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   pip install -r Fine-Tuning/requirements.txt
   ```

3. **Run Streamlit:**
   ```bash
   streamlit run app.py
   ```

4. **Or run the demo script:**
   ```bash
   python demo.py
   ```

## Usage

### Using the Web Interface

1. Select your **body type** (Longer Legs, Longer Torso, or Balanced)
2. Choose **mode** (Beginner or Pro)
3. Navigate to **Live Stream** or **Upload Video**
4. Enable **AI Feedback** for detailed personalized recommendations
5. Perform squats and get real-time feedback!

### Using the Demo Script

```bash
python demo.py
```

Follow the interactive prompts to:
- Select mode and body type
- Choose webcam or video file input
- View real-time analysis
- Save output video (optional)

## GPU Support (Optional)

For faster LLM inference, enable GPU support:

1. **Install NVIDIA Docker runtime:**
   ```bash
   # Ubuntu/Debian
   distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
   curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
   sudo apt-get update && sudo apt-get install -y nvidia-docker2
   sudo systemctl restart docker
   ```

2. **Uncomment GPU section in `docker-compose.yml`:**
   ```yaml
   deploy:
     resources:
       reservations:
         devices:
           - driver: nvidia
             count: 1
             capabilities: [gpu]
   ```

3. **Rebuild and run:**
   ```bash
   docker-compose up --build
   ```

## Documentation

- **Docker Setup**: See `DOCKER_README.md` for detailed Docker instructions
- **Model Training**: See `Fine-Tuning/README.md` for training instructions
- **API Documentation**: Check individual Python files for code documentation

## Troubleshooting

### Port Already in Use
Change the port in `docker-compose.yml`:
```yaml
ports:
  - "8502:8501"  # Use port 8502 instead
```

### Model Files Not Found
- LLM features won't work without model files
- Basic pose estimation will still function
- See "Set Up Model Files" section above

### Out of Memory
- Increase Docker memory limit in Docker Desktop settings
- Disable LLM features if not needed
- Use CPU-only mode (remove GPU configuration)

### Webcam Not Working
- **Linux**: Ensure proper device permissions
- **Windows/Mac**: Use the Streamlit web interface with WebRTC instead

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with Docker
5. Submit a pull request

## License

[Add your license here]

## Acknowledgments

- **MediaPipe** for pose estimation
- **Mistral AI** for the base language model
- **Streamlit** for the web framework

## Contact

[Add your contact information]

---

**Note**: This project is part of a research thesis on AI-powered fitness training. For academic use, please cite appropriately.

