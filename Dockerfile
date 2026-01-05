# Multi-stage build for AI Fitness Trainer
FROM python:3.10-slim as base

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements files
COPY requirements.txt .
COPY Fine-Tuning/requirements.txt Fine-Tuning/requirements.txt

# Install Python dependencies
# Install main requirements first
RUN pip install --no-cache-dir -r requirements.txt

# Install fine-tuning requirements (may have overlapping deps)
RUN pip install --no-cache-dir -r Fine-Tuning/requirements.txt

# Download NLTK data (needed for evaluation metrics)
RUN python -c "import nltk; nltk.download('punkt'); nltk.download('stopwords')"

# Copy application code
COPY . .

# Create directories for output videos
RUN mkdir -p /app/outputs

# Expose Streamlit port
EXPOSE 8501

# Health check (using curl instead of requests)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8501/_stcore/health || exit 1

# Default command: Run Streamlit app
# Streamlit will automatically detect the pages/ directory when running app.py
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--server.headless=true", "--server.enableCORS=false", "--server.enableXsrfProtection=false"]

