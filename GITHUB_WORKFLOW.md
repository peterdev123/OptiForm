# GitHub Workflow Guide

This document explains how to push this project to GitHub and how other users can pull and use it.

## For Repository Maintainers (You)

### Step 1: Prepare Your Repository

1. **Ensure all files are ready:**
   ```bash
   # Check what will be committed
   git status
   ```

2. **Important: Model Files**
   - Model files (`Fine-Tuning/mistral-7b-squat-qlora/`) are **large** (several GB)
   - They are excluded in `.gitignore` by default
   - **Options for handling models:**
     
     **Option A: Use Git LFS (Large File Storage)**
     ```bash
     # Install Git LFS
     git lfs install
     
     # Track model files with LFS
     git lfs track "Fine-Tuning/mistral-7b-squat-qlora/**/*.safetensors"
     git lfs track "Fine-Tuning/mistral-7b-squat-qlora/**/*.pt"
     git lfs track "Fine-Tuning/mistral-7b-squat-qlora/**/*.pth"
     git lfs track "Fine-Tuning/mistral-7b-squat-qlora/**/*.bin"
     
     # Add .gitattributes
     git add .gitattributes
     ```
     
     **Option B: Host Models Separately (Recommended)**
     - Upload models to cloud storage (Google Drive, Dropbox, HuggingFace)
     - Provide download link in README
     - Users download and place in correct directory
     
     **Option C: Don't Include Models**
     - Users train their own or download separately
     - Basic pose estimation works without models

### Step 2: Commit and Push

```bash
# Add all files (model files excluded by .gitignore)
git add .

# Commit
git commit -m "Add Docker support and complete project setup"

# Push to GitHub
git push origin main
```

### Step 3: Update README with Model Instructions

Make sure your README.md includes:
- How to get model files (download link or training instructions)
- Clear Docker setup instructions
- Prerequisites and system requirements

## For Other Users (Pulling and Using)

### Step 1: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/yourusername/ai-fitness-trainer-using-mediapipe.git

# Navigate to project directory
cd ai-fitness-trainer-using-mediapipe
```

### Step 2: Get Model Files (If Needed)

**If models are in Git LFS:**
```bash
# Pull LFS files
git lfs pull
```

**If models are hosted separately:**
```bash
# Download from provided link (e.g., Google Drive, HuggingFace)
# Place files in: Fine-Tuning/mistral-7b-squat-qlora/checkpoint-450/
```

**If training your own:**
```bash
# Follow instructions in Fine-Tuning/README.md
cd Fine-Tuning
python train_qlora.py
```

### Step 3: Run with Docker

```bash
# Build and run
docker-compose up --build

# Or use the quick start script
# Linux/Mac:
./docker-run.sh

# Windows:
docker-run.bat
```

### Step 4: Access the Application

Open browser: **http://localhost:8501**

## Complete Workflow Example

### Maintainer Side:
```bash
# 1. Make changes
git add .
git commit -m "Update Docker configuration"
git push origin main
```

### User Side:
```bash
# 1. Clone (first time) or pull (updates)
git clone <repo-url>                    # First time
# OR
git pull                                 # For updates

# 2. Get models (if needed)
# Download from link or use Git LFS

# 3. Run
docker-compose up --build
```

## What Gets Pushed to GitHub

**Included:**
- All Python source code
- Docker files (Dockerfile, docker-compose.yml)
- Requirements files
- Documentation (README, etc.)
- Configuration files

**Excluded (by .gitignore):**
- Model files (large binary files)
- Output videos
- Python cache files
- Environment files (.env)

## Best Practices

### For Maintainers:

1. **Keep repository size small**
   - Use `.gitignore` to exclude large files
   - Use Git LFS for necessary large files
   - Or host large files externally

2. **Document everything**
   - Clear README with setup instructions
   - Document where to get model files
   - Include troubleshooting section

3. **Test Docker setup**
   - Test on clean system before pushing
   - Ensure all dependencies are in requirements.txt
   - Verify Dockerfile builds successfully

### For Users:

1. **Check prerequisites**
   - Docker installed and running
   - Sufficient RAM (8GB+)
   - Model files downloaded (if needed)

2. **Follow instructions**
   - Read README.md first
   - Check DOCKER_README.md for Docker-specific issues
   - Review error messages carefully

3. **Report issues**
   - Include Docker logs: `docker logs ai-fitness-trainer`
   - Include system information
   - Check if issue is documented

## Common Issues

### Issue: "Model files not found"
**Solution:** Download model files and place in correct directory, or train your own.

### Issue: "Docker build fails"
**Solution:** 
- Check Docker is running: `docker ps`
- Check internet connection (needs to download base images)
- Check disk space: `docker system df`

### Issue: "Port 8501 already in use"
**Solution:** Change port in `docker-compose.yml` or stop other services using that port.

### Issue: "Out of memory"
**Solution:**
- Increase Docker memory limit
- Disable LLM features
- Use smaller batch sizes

## Summary

**The Workflow:**
1. **You push** → Code + Docker config to GitHub
2. **Users pull** → Clone repository
3. **Users get models** → Download or train
4. **Users run** → `docker-compose up`
5. **Users access** → http://localhost:8501

**Key Points:**
- Docker handles all dependencies automatically
- Model files need separate handling (too large for regular Git)
- Users don't need to install Python or dependencies manually
- Everything runs in isolated container

That's it! Docker makes distribution and setup much easier for users.

