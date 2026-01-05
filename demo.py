"""
Demo script for AI Fitness Trainer: Squats Analysis
Main source that runs MediaPipe pose estimation and feature extraction algorithm
Can be run standalone without Streamlit
"""

import cv2
import sys
from utils import get_mediapipe_pose
from process_frame import ProcessFrame
from thresholds import get_thresholds_beginner, get_thresholds_pro

def main():
    """Main function to run the squat analysis demo"""
    
    # Configuration
    print("AI Fitness Trainer: Squats Analysis - Demo")
    print("=" * 50)
    
    # Select mode
    mode = input("Select Mode (Beginner/Pro) [Default: Beginner]: ").strip().lower()
    if mode == 'pro':
        thresholds = get_thresholds_pro()
        print("Mode: Pro")
    else:
        thresholds = get_thresholds_beginner()
        print("Mode: Beginner")
    
    # Select body type
    print("\nBody Types:")
    print("1. N/A")
    print("2. Longer Legs")
    print("3. Longer Torso")
    print("4. Balanced")
    body_choice = input("Select Body Type (1-4) [Default: 1]: ").strip()
    
    body_type_mapping = {
        '1': 'N/A',
        '2': 'LONGER_LEGS',
        '3': 'LONGER_TORSO',
        '4': 'BALANCED'
    }
    body_type = body_type_mapping.get(body_choice, 'N/A')
    print(f"Body Type: {body_type}")
    
    # Initialize MediaPipe pose estimation
    print("\nInitializing MediaPipe pose estimation...")
    pose = get_mediapipe_pose()
    
    # Initialize ProcessFrame with thresholds and body type
    process_frame = ProcessFrame(thresholds=thresholds, flip_frame=False, body_type=body_type)
    
    # Select video source
    print("\nVideo Source Options:")
    print("1. Webcam (0)")
    print("2. Video file")
    source_choice = input("Select source (1-2) [Default: 1]: ").strip()
    
    if source_choice == '2':
        video_path = input("Enter video file path: ").strip()
        if not video_path:
            print("Error: No video path provided")
            return
        cap = cv2.VideoCapture(video_path)
    else:
        cap = cv2.VideoCapture(0)
    
    if not cap.isOpened():
        print("Error: Could not open video source")
        return
    
    # Get video properties
    fps = int(cap.get(cv2.CAP_PROP_FPS)) if source_choice == '2' else 30
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    
    print(f"\nVideo Properties: {width}x{height} @ {fps} FPS")
    print("\nPress 'q' to quit, 'r' to reset counters")
    print("=" * 50)
    
    # Optional: Save output video
    save_output = input("\nSave output video? (y/n) [Default: n]: ").strip().lower()
    video_writer = None
    if save_output == 'y':
        output_path = input("Enter output video path [Default: output_demo.mp4]: ").strip()
        if not output_path:
            output_path = "output_demo.mp4"
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        video_writer = cv2.VideoWriter(output_path, fourcc, fps, (width, height))
        print(f"Output will be saved to: {output_path}")
    
    # Main processing loop
    frame_count = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("\nEnd of video or failed to read frame")
                break
            
            # Convert BGR to RGB for MediaPipe
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Process frame with MediaPipe and feature extraction
            processed_frame, play_sound = process_frame.process(frame_rgb, pose)
            
            # Convert back to BGR for display
            display_frame = cv2.cvtColor(processed_frame, cv2.COLOR_RGB2BGR)
            
            # Display frame
            cv2.imshow('AI Fitness Trainer: Squats Analysis', display_frame)
            
            # Save frame if output video is enabled
            if video_writer is not None:
                video_writer.write(display_frame)
            
            # Handle keyboard input
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                print("\nQuitting...")
                break
            elif key == ord('r'):
                process_frame.state_tracker['SQUAT_COUNT'] = 0
                process_frame.state_tracker['IMPROPER_SQUAT'] = 0
                print("\nCounters reset")
            
            frame_count += 1
            
            # Print rep summaries when they're completed
            if len(process_frame.rep_summaries) > 0:
                last_rep = len(process_frame.rep_summaries) - 1
                if last_rep >= 0 and process_frame.last_summary:
                    print(f"\n[REP {last_rep + 1} SUMMARY]")
                    print(process_frame.last_summary)
                    print("-" * 50)
                    process_frame.last_summary = None  # Clear to avoid reprinting
    
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
    
    finally:
        # Cleanup
        print("\n" + "=" * 50)
        print("Session Summary:")
        print(f"Total Frames Processed: {frame_count}")
        print(f"Total Reps Completed: {process_frame.state_tracker['SQUAT_COUNT']}")
        print(f"Improper Squats: {process_frame.state_tracker['IMPROPER_SQUAT']}")
        
        if len(process_frame.rep_summaries) > 0:
            print("\nAll Rep Summaries:")
            for i, summary in enumerate(process_frame.rep_summaries, 1):
                print(f"\n[REP {i}]")
                print(summary)
        
        cap.release()
        if video_writer is not None:
            video_writer.release()
            print(f"\nOutput video saved to: {output_path}")
        cv2.destroyAllWindows()
        print("\nDemo completed!")

if __name__ == "__main__":
    main()

