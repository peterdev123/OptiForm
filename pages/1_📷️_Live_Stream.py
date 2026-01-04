import av
import os
import sys
import streamlit as st
from streamlit_webrtc import VideoHTMLAttributes, webrtc_streamer
from aiortc.contrib.media import MediaRecorder


BASE_DIR = os.path.abspath(os.path.join(__file__, '../../'))
sys.path.append(BASE_DIR)

if 'process_frame' in sys.modules:
    del sys.modules['process_frame']


from utils import get_mediapipe_pose
from process_frame import ProcessFrame
from thresholds import get_thresholds_beginner, get_thresholds_pro
from llm_feedback import load_llm_model, generate_feedback


st.title('AI Fitness Trainer: Squats Analysis')

mode = st.radio('Select Mode', ['Beginner', 'Pro'], horizontal=True)

thresholds = None 

if mode == 'Beginner':
    thresholds = get_thresholds_beginner()

elif mode == 'Pro':
    thresholds = get_thresholds_pro()

body_type_display = st.selectbox(
    'Body Type',
    ['N/A', 'Longer Legs', 'Longer Torso', 'Balanced'],
    help='Select your body proportion type. This helps customize squat form analysis based on your body structure. Unsure? Watch this guide: https://www.tiktok.com/@petitelife_incolors/video/7297635071089986862?lang=en'
)

st.markdown(
    '<small> <a href="https://www.tiktok.com/@petitelife_incolors/video/7297635071089986862?lang=en" target="_blank">Not sure about your body type? Watch this guide</a></small>',
    unsafe_allow_html=True
)

body_type_mapping = {
    'N/A': 'N/A',
    'Longer Legs': 'LONGER_LEGS',
    'Longer Torso': 'LONGER_TORSO',
    'Balanced': 'BALANCED'
}
body_type = body_type_mapping.get(body_type_display, 'N/A')

# LLM Feedback Option
use_llm_feedback = st.checkbox('Enable AI Feedback (LLM)', value=False, 
                                help='Generate detailed AI-powered feedback for each rep using the fine-tuned language model')

# Load model at startup if LLM feedback is enabled (or reuse if already loaded)
llm_model = None
llm_tokenizer = None
if use_llm_feedback:
    if 'llm_model_loaded' not in st.session_state or not st.session_state.get('llm_model_loaded', False):
        with st.spinner('Loading AI model (this may take a minute)...'):
            llm_model, llm_tokenizer = load_llm_model()
            if llm_model is not None and llm_tokenizer is not None:
                st.session_state['llm_model'] = llm_model
                st.session_state['llm_tokenizer'] = llm_tokenizer
                st.session_state['llm_model_loaded'] = True
                st.success('AI model loaded successfully!')
            else:
                st.error('Failed to load AI model. Please check if the model files are available.')
                use_llm_feedback = False
    else:
        # Reuse already loaded model (faster)
        llm_model = st.session_state.get('llm_model')
        llm_tokenizer = st.session_state.get('llm_tokenizer')
elif 'llm_model_loaded' in st.session_state and st.session_state.get('llm_model_loaded', False):
    # Model is loaded but checkbox is unchecked - keep it loaded for faster re-enabling
    llm_model = st.session_state.get('llm_model')
    llm_tokenizer = st.session_state.get('llm_tokenizer')

live_process_frame = ProcessFrame(thresholds=thresholds, flip_frame=True, body_type=body_type)
# Initialize face mesh solution
pose = get_mediapipe_pose()

# Initialize session state for tracking reps
if 'rep_feedbacks' not in st.session_state:
    st.session_state['rep_feedbacks'] = []
if 'last_rep_count' not in st.session_state:
    st.session_state['last_rep_count'] = 0

if 'download' not in st.session_state:
    st.session_state['download'] = False

output_video_file = f'output_live.flv'

def video_frame_callback(frame: av.VideoFrame):
    frame = frame.to_ndarray(format="rgb24")  # Decode and get RGB frame
    frame, _ = live_process_frame.process(frame, pose)  # Process frame
    return av.VideoFrame.from_ndarray(frame, format="rgb24")  # Encode and return BGR frame

def out_recorder_factory() -> MediaRecorder:
        return MediaRecorder(output_video_file)

ctx = webrtc_streamer(
                        key="Squats-pose-analysis",
                        video_frame_callback=video_frame_callback,
                        rtc_configuration={"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]},  # Add this config
                        media_stream_constraints={"video": {"width": {'min':480, 'ideal':480}}, "audio": False},
                        video_html_attrs=VideoHTMLAttributes(autoPlay=True, controls=False, muted=False),
                        out_recorder_factory=out_recorder_factory
                    )

download_button = st.empty()

# Feedback display area
feedback_container = st.sidebar.container()

# Check for new reps and generate feedback
# For live stream, we check after stream stops or periodically
if use_llm_feedback and llm_model is not None and llm_tokenizer is not None:
    try:
        current_rep_count = len(live_process_frame.rep_summaries) if hasattr(live_process_frame, 'rep_summaries') else 0
        if current_rep_count > st.session_state['last_rep_count']:
            # New rep completed - generate feedback immediately (model is already loaded)
            new_rep_index = st.session_state['last_rep_count']
            if new_rep_index < len(live_process_frame.rep_summaries):
                summary = live_process_frame.rep_summaries[new_rep_index]
                # Generate feedback without spinner (faster since model is loaded)
                feedback = generate_feedback(summary, llm_model, llm_tokenizer)
                if feedback:
                    st.session_state['rep_feedbacks'].append({
                        'rep': current_rep_count,
                        'summary': summary,
                        'feedback': feedback
                    })
            st.session_state['last_rep_count'] = current_rep_count
    except Exception as e:
        # If accessing rep_summaries fails (callback context issue), handle gracefully
        pass
    
    # Display feedbacks
    if len(st.session_state['rep_feedbacks']) > 0:
        feedback_container.markdown("---")
        feedback_container.markdown("### AI Feedback")
        for fb_data in st.session_state['rep_feedbacks']:
            with feedback_container.expander(f"Rep {fb_data['rep']} Feedback", expanded=False):
                feedback_container.markdown("**Form Summary:**")
                feedback_container.text(fb_data['summary'])
                feedback_container.markdown("**AI Feedback:**")
                feedback_container.write(fb_data['feedback'])
    
    # Button to manually generate feedback for all reps (if stream ended)
    if not ctx.state.playing:
        try:
            current_rep_count = len(live_process_frame.rep_summaries) if hasattr(live_process_frame, 'rep_summaries') else 0
            if current_rep_count > len(st.session_state['rep_feedbacks']):
                if st.sidebar.button("Generate Feedback for All Reps"):
                    with st.spinner('Generating AI feedback for all reps...'):
                        for i, summary in enumerate(live_process_frame.rep_summaries, 1):
                            if i > len(st.session_state['rep_feedbacks']):
                                feedback = generate_feedback(summary, llm_model, llm_tokenizer)
                                if feedback:
                                    st.session_state['rep_feedbacks'].append({
                                        'rep': i,
                                        'summary': summary,
                                        'feedback': feedback
                                    })
                        st.rerun()
        except:
            pass

if os.path.exists(output_video_file):
    with open(output_video_file, 'rb') as op_vid:
        download = download_button.download_button('Download Video', data = op_vid, file_name='output_live.flv')

        if download:
            st.session_state['download'] = True



if os.path.exists(output_video_file) and st.session_state['download']:
    os.remove(output_video_file)
    st.session_state['download'] = False
    download_button.empty()


    


