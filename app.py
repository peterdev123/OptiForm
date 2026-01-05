"""
Main Streamlit application entry point for AI Fitness Trainer
This file serves as the entry point when running with Docker or directly
"""

import streamlit as st

# Set page config
st.set_page_config(
    page_title="AI Fitness Trainer: Squats Analysis",
    page_icon=None,
    layout="wide",
    initial_sidebar_state="expanded"
)

# Main title
st.title("AI Fitness Trainer: Squats Analysis")
st.markdown("---")

# Welcome message
st.markdown("""
Welcome to the AI Fitness Trainer! This application uses computer vision and AI to analyze your squat form.

### Features:
- **Real-time Pose Estimation**: Uses MediaPipe to detect body landmarks
- **Form Analysis**: Analyzes squat depth, posture, and common form issues
- **AI-Powered Feedback**: Get personalized feedback using a fine-tuned language model
- **Multiple Modes**: Beginner and Pro modes with different thresholds

### Navigation:
Use the sidebar to navigate between:
- **Live Stream**: Analyze squats in real-time using your webcam
- **Upload Video**: Upload and analyze a recorded video

### Getting Started:
1. Select your body type (helps customize analysis)
2. Choose Beginner or Pro mode
3. Navigate to Live Stream or Upload Video
4. Enable AI Feedback for detailed personalized recommendations
""")

st.markdown("---")
st.info("**Tip**: For best results, ensure good lighting and a clear view of your full body during squats.")

