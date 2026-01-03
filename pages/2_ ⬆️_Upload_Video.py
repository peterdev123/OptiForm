import av
import os
import sys
import streamlit as st
import cv2
import tempfile


BASE_DIR = os.path.abspath(os.path.join(__file__, '../../'))
sys.path.append(BASE_DIR)

if 'process_frame' in sys.modules:
    del sys.modules['process_frame']


from utils import get_mediapipe_pose
from process_frame import ProcessFrame
from thresholds import get_thresholds_beginner, get_thresholds_pro



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

upload_process_frame = ProcessFrame(thresholds=thresholds, body_type=body_type)

pose = get_mediapipe_pose()


download = None

if 'download' not in st.session_state:
    st.session_state['download'] = False

if 'uploaded_file' not in st.session_state:
    st.session_state['uploaded_file'] = None

if 'file_processed' not in st.session_state:
    st.session_state['file_processed'] = False

output_video_file = f'output_recorded.mp4'

if os.path.exists(output_video_file) and st.session_state['file_processed']:
    os.remove(output_video_file)
    st.session_state['file_processed'] = False


with st.form('Upload', clear_on_submit=True):
    up_file = st.file_uploader("Upload a Video", ['mp4','mov', 'avi'])
    uploaded = st.form_submit_button("Upload")
    
    if up_file is not None:
        up_file.seek(0)
        file_bytes = up_file.read()
        st.session_state['uploaded_file'] = file_bytes
        st.session_state['file_processed'] = False
        st.session_state['should_process'] = True
    elif uploaded:
        if st.session_state.get('uploaded_file') is None:
            st.session_state['should_process'] = False

if 'should_process' not in st.session_state:
    st.session_state['should_process'] = False

stframe = st.empty()

ip_vid_str = '<p style="font-family:Helvetica; font-weight: bold; font-size: 16px;">Input Video</p>'
warning_str = '<p style="font-family:Helvetica; font-weight: bold; color: Red; font-size: 17px;">Please Upload a Video first!!!</p>'

warn = st.empty()

download_button = st.empty()

if st.session_state.get('should_process', False) and st.session_state.get('uploaded_file') is not None:
    st.session_state['should_process'] = False
    file_bytes = st.session_state['uploaded_file']
    
    download_button.empty()
    tfile = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')

    try:
        warn.empty()
        tfile.write(file_bytes)
        tfile.flush()
        tfile.seek(0)

        vf = cv2.VideoCapture(tfile.name)
        
        if not vf.isOpened():
            warn.markdown(warning_str, unsafe_allow_html=True)
            tfile.close()
        else:
            fps = int(vf.get(cv2.CAP_PROP_FPS))
            width = int(vf.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(vf.get(cv2.CAP_PROP_FRAME_HEIGHT))
            frame_size = (width, height)
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            video_output = cv2.VideoWriter(output_video_file, fourcc, fps, frame_size)

            
            txt = st.sidebar.markdown(ip_vid_str, unsafe_allow_html=True)   
            ip_video = st.sidebar.video(tfile.name) 

            while vf.isOpened():
                ret, frame = vf.read()
                if not ret:
                    break

                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                out_frame, _ = upload_process_frame.process(frame, pose)
                stframe.image(out_frame)
                video_output.write(out_frame[...,::-1])

            
            vf.release()
            video_output.release()
            stframe.empty()
            ip_video.empty()
            txt.empty()
            
            tfile.close()
            
            try:
                if os.path.exists(tfile.name):
                    os.unlink(tfile.name)
            except PermissionError:
                pass
            except Exception:
                pass
            
            st.session_state['file_processed'] = True
    except Exception as e:
        error_msg = f'<p style="font-family:Helvetica; font-weight: bold; color: Red; font-size: 17px;">Error: {str(e)}</p>'
        warn.markdown(error_msg, unsafe_allow_html=True)
        if 'vf' in locals() and vf.isOpened():
            vf.release()
        if 'video_output' in locals():
            video_output.release()
        if 'tfile' in locals():
            try:
                tfile.close()
            except:
                pass
            try:
                if os.path.exists(tfile.name):
                    os.unlink(tfile.name)
            except (PermissionError, OSError):
                pass
            except Exception:
                pass
    else:
        warn.markdown(warning_str, unsafe_allow_html=True)


if os.path.exists(output_video_file) and st.session_state['file_processed']:
    with open(output_video_file, 'rb') as op_vid:
        download = download_button.download_button('Download Video', data = op_vid, file_name='output_recorded.mp4')
    
    if download:
        st.session_state['download'] = True



if os.path.exists(output_video_file) and st.session_state['download']:
    os.remove(output_video_file)
    st.session_state['download'] = False
    download_button.empty()
