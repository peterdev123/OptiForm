# Quick Start Guide

## For You (Pushing to GitHub)

```bash
# 1. Add all files
git add .

# 2. Commit
git commit -m "Add Docker support"

# 3. Push to GitHub
git push origin main
```

**That's it!** Your code is now on GitHub.

## For Other Users (Pulling and Running)

```bash
# 1. Clone your repository
git clone https://github.com/yourusername/ai-fitness-trainer-using-mediapipe.git
cd ai-fitness-trainer-using-mediapipe

# 2. Get model files (if needed - see README for options)
# Option A: Download from your provided link
# Option B: Train their own
# Option C: Skip (basic features work without models)

# 3. Run with Docker
docker-compose up --build

# 4. Open browser
# Go to: http://localhost:8501
```

**That's it!** They're running your app.

## What Happens Behind the Scenes

1. **Docker builds** the image with all dependencies
2. **Docker runs** the container with your code
3. **Streamlit starts** the web server
4. **Users access** it in their browser

No manual Python installation needed!

## Important Notes

- **Model files** are large (several GB) - handle separately (see GITHUB_WORKFLOW.md)
- **Docker must be installed** on users' machines
- **Port 8501** must be available

## More Details

- Full workflow: See `GITHUB_WORKFLOW.md`
- Docker setup: See `DOCKER_README.md`
- Project overview: See `README.md`

