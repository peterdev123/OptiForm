import time
import os
import csv
import cv2
import numpy as np
from utils import find_angle, get_landmark_features, draw_text, draw_dotted_line, draw_dotted_hline, get_landmark_array

__all__ = ['ProcessFrame']


class ProcessFrame:
    """
      - derive angles and draw guides
      - track squat states and inactivity
      - detect key cues (torso forward, knees past toes, heel lift)
      - summarize reps with peak/last snapshots
    """
    def __init__(self, thresholds, flip_frame = False, body_type = 'N/A'):
        """Configure drawing, thresholds, and state trackers.
        
        Args:
            thresholds: Dictionary of threshold values for form detection
            flip_frame: Whether to flip the frame horizontally
            body_type: User's body type ('LONGER_LEGS', 'LONGER_TORSO', 'BALANCED', or 'N/A')
        """
        
        # Set if frame should be flipped or not.
        self.flip_frame = flip_frame

        # self.thresholds
        self.thresholds = thresholds

        # Font type.
        self.font = cv2.FONT_HERSHEY_SIMPLEX

        # line type
        self.linetype = cv2.LINE_AA

        # set radius to draw arc
        self.radius = 20
        self.COLORS = {
                        'blue'       : (0, 127, 255),   
                        'red'        : (0, 64, 255),    
                        'green'      : (0, 255, 0),    
                        'light_green': (147, 58, 255),  
                        'yellow'     : (0, 255, 255),   
                        'magenta'    : (255, 0, 255),   
                        'white'      : (255, 255, 255), 
                        'cyan'       : (255, 255, 0),   
                        'light_blue' : (219, 112, 147)  
                      }



        # ---------------- MediaPipe landmark index maps ----------------
        self.dict_features = {}
        self.left_features = {
                                'shoulder': 11,
                                'elbow'   : 13,
                                'hip'     : 23,
                                'knee'    : 25,
                                'ankle'   : 27,
                                'heel'    : 29,
                                'foot'    : 31,
                                'wrist'   : 15
                             }

        self.right_features = {
                                'shoulder': 12,
                                'elbow'   : 14,
                                'hip'     : 24,
                                'knee'    : 26,
                                'ankle'   : 28,
                                'heel'    : 30,
                                'foot'    : 32,
                                'wrist'   : 16
                              }

        self.dict_features['left'] = self.left_features
        self.dict_features['right'] = self.right_features
        self.dict_features['nose'] = 0

        
        # ------------------ State machine and counters ------------------
        self.state_tracker = {
            'state_seq': [],

            'start_inactive_time': time.perf_counter(),
            'start_inactive_time_front': time.perf_counter(),
            'INACTIVE_TIME': 0.0,
            'INACTIVE_TIME_FRONT': 0.0,

            # 0 --> Bend Backwards, 1 --> Bend Forward, 2 --> Keep shin straight, 3 --> Deep squat
            'DISPLAY_TEXT' : np.full((4,), False),
            'COUNT_FRAMES' : np.zeros((4,), dtype=np.int64),

            'LOWER_HIPS': False,

            'INCORRECT_POSTURE': False,

            'prev_state': None,
            'curr_state':None,

            'SQUAT_COUNT': 0,
			'IMPROPER_SQUAT':0,
            
        }
        
        self.headstart_sec = 4
        self._created_at = time.perf_counter()
        
        # ---------------- Per-rep maxima (for summary) -----------------
        self.angle_maxima = {
            'back': 0,
            'knee': 0,
            'ankle': 0,
            'heel': 0
        }
        self.min_log_angle = {
            'back': 20,  
            'knee': 0,
            'ankle': 0,
            'heel': 0
        }
        self.rep_index = 0
        self.rep_summaries = []
        self.last_summary = None
        self.rep_feedbacks = []  # Store LLM feedback for each rep
        self.rep_metrics = []
        # Where to persist metrics so Streamlit / demo runs both log data
        self._metrics_csv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rep_metrics_stream.csv")
        self._metrics_csv_initialized = False
        self.rep_flags = {
            'torso_forward': False,     
            'knees_past_toes': False,   
            'elbow_flaring': False,     
            'heels_lifting': False      
        }
        self.event_snapshots = {
            'torso_forward': None,       
            'knees_past_toes': None,
            'heels_lifting': None       
        }
        self.snapshot_thresholds = {
            'heel_distance': 25,
            'torso_hip_angle': 45
        }
        self.body_type = body_type if body_type in ['LONGER_LEGS', 'LONGER_TORSO', 'BALANCED', 'N/A'] else 'N/A'
        self.max_heel_distance = 0
        self.knee_toe_offset_ratio = 0.04     
        self.knee_toe_min_px = 15           
        self.shoulder_knee_offset_ratio = 0.06
        self.shoulder_knee_min_px = 17
        self.heel_lift_thresh = 25
        self.smooth_alpha_common = 0.25
        self.visibility_thresh_common = 0.5
        self.max_jump_ratio = 0.05 
        self.prev_coords = {'left': {}, 'right': {}}
        self.elbow_flare_thresh = 25
        self.elbow_flare_min_angle = None
        # ---------------- Landmark smoothing (elbow) -------------------
        self.prev_elbow_coord = None
        self.prev_upper_side = None 
        self.elbow_smooth_alpha = 0.25
        self.elbow_visibility_thresh = 0.5
        
        
        self.FEEDBACK_ID_MAP = {
                                0: ('BEND BACKWARDS', 215, (0, 128, 255)),   
                                1: ('BEND FORWARD', 215, (0, 128, 255)),     
                                2: ('KNEE FALLING OVER TOE', 170, (255, 0, 128)), 
                                3: ('SQUAT TOO DEEP', 125, (255, 0, 128))    
                               }

        


    def _get_state(self, knee_angle):
        """Map knee vertical angle into coarse squat state s1/s2/s3."""

        normal_lo, normal_hi = self.thresholds['HIP_KNEE_VERT']['NORMAL']
        trans_lo, trans_hi   = self.thresholds['HIP_KNEE_VERT']['TRANS']
        pass_lo, pass_hi     = self.thresholds['HIP_KNEE_VERT']['PASS']

        if knee_angle <= normal_hi:
            return 's1'
        elif knee_angle <= trans_hi:
            return 's2'
        else:
            return 's3'
    
    def _update_state_sequence(self, state):
        """Maintain valid state sequence within a rep (s2 then s3)."""

        if state == 's2':
            if (('s3' not in self.state_tracker['state_seq']) and (self.state_tracker['state_seq'].count('s2'))==0) or \
                    (('s3' in self.state_tracker['state_seq']) and (self.state_tracker['state_seq'].count('s2')==1)):
                        self.state_tracker['state_seq'].append(state)
            

        elif state == 's3':
            if (state not in self.state_tracker['state_seq']) and 's2' in self.state_tracker['state_seq']: 
                self.state_tracker['state_seq'].append(state)

    def _show_feedback(self, frame, c_frame, dict_maps, lower_hips_disp):
        """Render transient text feedback (no-op override point)."""
        return frame
    def _log_angle(self, key, angle_value):
        """Track maximum angle per key during an active squat window."""
        if (time.perf_counter() - self._created_at) < self.headstart_sec:
            return
        if self.state_tracker.get('curr_state') not in ('s2','s3'):
            return
        if angle_value >= self.min_log_angle.get(key, 0) and angle_value > self.angle_maxima.get(key, 0):
            self.angle_maxima[key] = angle_value

    def _reset_angle_maxima(self):
        """Reset per-rep maxima."""
        self.angle_maxima['back'] = 0
        self.angle_maxima['knee'] = 0
        self.angle_maxima['ankle'] = 0
        self.angle_maxima['heel'] = 0
    
    def _smooth_landmark(self, side, name, lm_index, kp_results, frame_width, frame_height):
        """
        Smooth a single landmark:
          - gate by visibility
          - clamp max jump per frame
          - exponential moving average
        Returns an int np.array([x, y]).
        """
        curr = get_landmark_array(kp_results, lm_index, frame_width, frame_height)
        vis = getattr(kp_results[lm_index], 'visibility', 1.0)
        prev = self.prev_coords[side].get(name)
        if vis < self.visibility_thresh_common and prev is not None:
            return prev
        if prev is None:
            smoothed = curr
        else:
            max_jump_px = max(8, int(self.max_jump_ratio * frame_width))
            dx = curr[0] - prev[0]
            dy = curr[1] - prev[1]
            if abs(dx) > max_jump_px:
                dx = max_jump_px if dx > 0 else -max_jump_px
            if abs(dy) > max_jump_px:
                dy = max_jump_px if dy > 0 else -max_jump_px
            clamped = np.array([prev[0] + dx, prev[1] + dy])
            alpha = self.smooth_alpha_common
            sm = (1.0 - alpha) * prev + alpha * clamped
            smoothed = np.array([int(sm[0]), int(sm[1])])
        self.prev_coords[side][name] = smoothed
        return smoothed

    def _format_body_type(self, body_type):
        """Convert body type from code format to readable format."""
        mapping = {
            'LONGER_LEGS': 'Longer Legs',
            'LONGER_TORSO': 'Longer Torso',
            'BALANCED': 'Balanced',
            'N/A': 'N/A'
        }
        return mapping.get(body_type, 'N/A')

    def _finalize_rep(self):
        """Build and store the rep summary in clean, readable format."""
        self.rep_index += 1
        
        max_knee_flexion = self.angle_maxima['knee']
        depth_reached_90 = 75 <= max_knee_flexion <= 90
        
        has_heels_lifting = self.rep_flags.get('heels_lifting', False)
        has_torso_forward = self.rep_flags.get('torso_forward', False)
        has_knees_forward = self.rep_flags.get('knees_past_toes', False)
        has_elbow_flaring = self.rep_flags.get('elbow_flaring', False) and \
                           (self.elbow_flare_min_angle is not None and self.elbow_flare_min_angle < self.elbow_flare_thresh)
        
        is_acceptable = not (has_heels_lifting or has_torso_forward or has_knees_forward or has_elbow_flaring or not depth_reached_90)
        
        body_type_formatted = self._format_body_type(self.body_type)

        snapshot = None
        if has_heels_lifting and self.event_snapshots['heels_lifting'] is not None:
            snapshot = self.event_snapshots['heels_lifting']
        elif has_torso_forward and self.event_snapshots['torso_forward'] is not None:
            snapshot = self.event_snapshots['torso_forward']
        elif has_knees_forward and self.event_snapshots['knees_past_toes'] is not None:
            snapshot = self.event_snapshots['knees_past_toes']

        if snapshot is not None:
            back_val = int(snapshot.get('torso_hip_angle', self.angle_maxima.get('back', 0)))
            ankle_val = int(snapshot.get('ankle_angle', self.angle_maxima.get('ankle', 0)))
            # Match the printed heel value: heel_distance - 20
            heel_val = int(snapshot.get('heel_distance', 0)) - 20
            if heel_val < 0:
                heel_val = 0
        else:
            back_val = int(self.angle_maxima.get("back", 0))
            ankle_val = int(self.angle_maxima.get("ankle", 0))
            heel_val = int(self.angle_maxima.get("heel", 0))

        knee_val = int(max_knee_flexion) if max_knee_flexion > 0 else 0

        rep_row = {
            "back_angle_max": back_val,
            "knee_angle_max": knee_val,
            "ankle_angle_max": ankle_val,
            "heel_angle_max": heel_val,
            "elbow_angle_min": int(self.elbow_flare_min_angle) if self.elbow_flare_min_angle is not None else 0,
            "depth_low": 1 if knee_val < 75 else 0,
            "heels_lifting": 1 if has_heels_lifting else 0,
            "torso_forward": 1 if has_torso_forward else 0,
            "knees_past_toes": 1 if has_knees_forward else 0,
            "elbow_flaring": 1 if has_elbow_flaring else 0,
            "acceptable": 1 if is_acceptable else 0,
        }
        self.rep_metrics.append(rep_row)
        self._append_metrics_csv(rep_row)
        
        summary_lines = []
        summary_lines.append(f"Rep Number: {self.rep_index}")
        summary_lines.append(f"Body Type: {body_type_formatted}")
        
        if has_heels_lifting and self.event_snapshots['heels_lifting'] is not None:
            s = self.event_snapshots['heels_lifting']
            summary_lines.append(f"Heels Lifting: TRUE (torso-hip: {int(s['torso_hip_angle'])}, ankle: {int(s['ankle_angle'])}, heel: {int(s['heel_distance']) - 20})")
        else:
            summary_lines.append("Heels Lifting: FALSE")
        
        if has_torso_forward and self.event_snapshots['torso_forward'] is not None:
            s = self.event_snapshots['torso_forward']
            summary_lines.append(f"Torso Forward: TRUE (torso-hip: {int(s['torso_hip_angle'])}, ankle: {int(s['ankle_angle'])}, heel: {int(s['heel_distance'])  - 20})")
        else:
            summary_lines.append("Torso Forward: FALSE")
        
        if has_knees_forward:
            if has_heels_lifting and self.event_snapshots['heels_lifting'] is not None and self.event_snapshots['heels_lifting']['ankle_angle'] > 40:
                s = self.event_snapshots['heels_lifting']
                summary_lines.append(f"Knees Forward: TRUE (torso-hip: {int(s['torso_hip_angle'])}, ankle: {int(s['ankle_angle'])}, heel: {int(s['heel_distance'])  - 20})")
            elif self.event_snapshots['knees_past_toes'] is not None:
                s = self.event_snapshots['knees_past_toes']
                summary_lines.append(f"Knees Forward: TRUE (torso-hip: {int(s['torso_hip_angle'])}, ankle: {int(s['ankle_angle'])}, heel: {int(s['heel_distance']) - 20})")
            else:
                summary_lines.append("Knees Forward: TRUE")
        else:
            summary_lines.append("Knees Forward: FALSE")
        
        if has_elbow_flaring and self.elbow_flare_min_angle is not None:
            summary_lines.append(f"Elbow Flaring: TRUE ({int(self.elbow_flare_min_angle)})")
        else:
            summary_lines.append("Elbow Flaring: FALSE")
        
        depth_value = int(max_knee_flexion) if max_knee_flexion > 0 else 0
        summary_lines.append(f"Depth: {depth_value}")
        
        summary_lines.append(f"Acceptable: {'TRUE' if is_acceptable else 'FALSE'}")
        
        summary = "\n".join(summary_lines)
        print(summary, flush=True)
        self.rep_summaries.append(summary)
        self.last_summary = summary

    def _append_metrics_csv(self, rep_row):
        """Append a rep's metrics to a CSV file for offline analysis.

        This is called every time a rep is finalized so it works both in
        plain Python runs and when invoked via `streamlit run`.
        """
        try:
            fieldnames = [
                "back_angle_max",
                "knee_angle_max",
                "ankle_angle_max",
                "heel_angle_max",
                "elbow_angle_min",
                "depth_low",
                "heels_lifting",
                "torso_forward",
                "knees_past_toes",
                "elbow_flaring",
                "acceptable",
            ]
            file_exists = os.path.isfile(self._metrics_csv_path)
            mode = "a" if file_exists else "w"
            with open(self._metrics_csv_path, mode, newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                if not file_exists:
                    writer.writeheader()
                writer.writerow({k: rep_row.get(k) for k in fieldnames})
        except Exception:
            # Logging must never break the main pose pipeline.
            pass




    def process(self, frame: np.array, pose):
        """
          - estimate landmarks
          - choose the visible side
          - compute/draw geometry
          - update cues, state, and summaries
        Returns: (frame, optional_sound_key)
        """
        play_sound = None
       

        frame_height, frame_width, _ = frame.shape

        # Process the image.
        keypoints = pose.process(frame)

        if keypoints.pose_landmarks:
            ps_lm = keypoints.pose_landmarks

            nose_coord = get_landmark_features(ps_lm.landmark, self.dict_features, 'nose', frame_width, frame_height)
            left_shldr_coord, left_hip_coord, left_knee_coord, left_ankle_coord, left_heel_coord, left_foot_coord = \
                                get_landmark_features(ps_lm.landmark, self.dict_features, 'left', frame_width, frame_height)
            right_shldr_coord, right_hip_coord, right_knee_coord, right_ankle_coord, right_heel_coord, right_foot_coord = \
                                get_landmark_features(ps_lm.landmark, self.dict_features, 'right', frame_width, frame_height)

            offset_angle = find_angle(left_shldr_coord, right_shldr_coord, nose_coord)

            if offset_angle > self.thresholds['OFFSET_THRESH']:
                
                display_inactivity = False

                end_time = time.perf_counter()
                self.state_tracker['INACTIVE_TIME_FRONT'] += end_time - self.state_tracker['start_inactive_time_front']
                self.state_tracker['start_inactive_time_front'] = end_time

                if self.state_tracker['INACTIVE_TIME_FRONT'] >= self.thresholds['INACTIVE_THRESH']:
                    self.state_tracker['SQUAT_COUNT'] = 0
                    self.state_tracker['IMPROPER_SQUAT'] = 0
                    display_inactivity = True

                cv2.circle(frame, nose_coord, 7, self.COLORS['white'], -1)
                cv2.circle(frame, left_shldr_coord, 7, self.COLORS['yellow'], -1)
                cv2.circle(frame, right_shldr_coord, 7, self.COLORS['magenta'], -1)

                if self.flip_frame:
                    frame = cv2.flip(frame, 1)

                if display_inactivity:
                    play_sound = 'reset_counters'
                    self.state_tracker['INACTIVE_TIME_FRONT'] = 0.0
                    self.state_tracker['start_inactive_time_front'] = time.perf_counter()



                self.state_tracker['start_inactive_time'] = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] = 0.0
                self.state_tracker['prev_state'] =  None
                self.state_tracker['curr_state'] = None
            
            else:

                self.state_tracker['INACTIVE_TIME_FRONT'] = 0.0
                self.state_tracker['start_inactive_time_front'] = time.perf_counter()


                dist_l_sh_hip = abs(left_foot_coord[1] - left_shldr_coord[1])
                dist_r_sh_hip = abs(right_foot_coord[1] - right_shldr_coord[1])

                shldr_coord = None
                
                hip_coord = None
                knee_coord = None
                ankle_coord = None
                heel_coord = None
                foot_coord = None

                if dist_l_sh_hip > dist_r_sh_hip:
                    hip_coord = self._smooth_landmark('left', 'hip', self.left_features['hip'], ps_lm.landmark, frame_width, frame_height)
                    knee_coord = self._smooth_landmark('left', 'knee', self.left_features['knee'], ps_lm.landmark, frame_width, frame_height)
                    ankle_coord = self._smooth_landmark('left', 'ankle', self.left_features['ankle'], ps_lm.landmark, frame_width, frame_height)
                    heel_coord = self._smooth_landmark('left', 'heel', self.left_features['heel'], ps_lm.landmark, frame_width, frame_height)
                    foot_coord = self._smooth_landmark('left', 'foot', self.left_features['foot'], ps_lm.landmark, frame_width, frame_height)
                    shldr_coord = self._smooth_landmark('left', 'shoulder', self.left_features['shoulder'], ps_lm.landmark, frame_width, frame_height)
                    current_side = 'left'
                    if self.prev_upper_side != current_side:
                        self.prev_elbow_coord = None
                        self.prev_upper_side = current_side
                    elbow_idx = self.left_features['elbow']
                    elbow_vis = getattr(ps_lm.landmark[elbow_idx], 'visibility', 1.0)
                    elbow_curr = get_landmark_array(ps_lm.landmark, elbow_idx, frame_width, frame_height)
                    if elbow_vis < self.elbow_visibility_thresh and self.prev_elbow_coord is not None:
                        elbow_coord = self.prev_elbow_coord
                    else:
                        if self.prev_elbow_coord is None:
                            elbow_coord = elbow_curr
                        else:
                            alpha = self.elbow_smooth_alpha
                            smoothed = (1.0 - alpha) * self.prev_elbow_coord + alpha * elbow_curr
                            elbow_coord = np.array([int(smoothed[0]), int(smoothed[1])])
                    self.prev_elbow_coord = elbow_coord

                    multiplier = -1
                                     
                
                else:
                    hip_coord = self._smooth_landmark('right', 'hip', self.right_features['hip'], ps_lm.landmark, frame_width, frame_height)
                    knee_coord = self._smooth_landmark('right', 'knee', self.right_features['knee'], ps_lm.landmark, frame_width, frame_height)
                    ankle_coord = self._smooth_landmark('right', 'ankle', self.right_features['ankle'], ps_lm.landmark, frame_width, frame_height)
                    heel_coord = self._smooth_landmark('right', 'heel', self.right_features['heel'], ps_lm.landmark, frame_width, frame_height)
                    foot_coord = self._smooth_landmark('right', 'foot', self.right_features['foot'], ps_lm.landmark, frame_width, frame_height)
                    shldr_coord = self._smooth_landmark('right', 'shoulder', self.right_features['shoulder'], ps_lm.landmark, frame_width, frame_height)
                    current_side = 'right'
                    # Reset smoothing when side switches
                    if self.prev_upper_side != current_side:
                        self.prev_elbow_coord = None
                        self.prev_upper_side = current_side
                    elbow_idx = self.right_features['elbow']
                    elbow_vis = getattr(ps_lm.landmark[elbow_idx], 'visibility', 1.0)
                    elbow_curr = get_landmark_array(ps_lm.landmark, elbow_idx, frame_width, frame_height)
                    if elbow_vis < self.elbow_visibility_thresh and self.prev_elbow_coord is not None:
                        elbow_coord = self.prev_elbow_coord
                    else:
                        if self.prev_elbow_coord is None:
                            elbow_coord = elbow_curr
                        else:
                            alpha = self.elbow_smooth_alpha
                            smoothed = (1.0 - alpha) * self.prev_elbow_coord + alpha * elbow_curr
                            elbow_coord = np.array([int(smoothed[0]), int(smoothed[1])])
                    self.prev_elbow_coord = elbow_coord

                    multiplier = 1
                    
                # ------------------- Shoulder vertical guide and torso-forward check --------------
                short_end = min(frame_height - 1, shldr_coord[1] + 32)
                draw_dotted_line(frame, shldr_coord, start=shldr_coord[1], end=short_end, line_color=self.COLORS['blue'])
                hline_len = max(60, int(0.1 * frame_width))
                if multiplier == 1:
                    hstart_x = max(0, shldr_coord[0] - hline_len)
                    hend_x = shldr_coord[0]
                else:
                    hstart_x = shldr_coord[0]
                    hend_x = min(frame_width - 1, shldr_coord[0] + hline_len)
                draw_dotted_hline(frame, shldr_coord[1], min(hstart_x, hend_x), max(hstart_x, hend_x), self.COLORS['blue'])
                early_toe_tol = max(self.knee_toe_min_px, int(self.knee_toe_offset_ratio * frame_width))
                torso_too_forward = (shldr_coord[0] > foot_coord[0] + early_toe_tol) if (multiplier == 1) else (shldr_coord[0] < foot_coord[0] - early_toe_tol)
                # ------------------- Knee-to-toes inline guide and check --------------
                toes_start = max(0, foot_coord[1] - 32)
                draw_dotted_line(frame, foot_coord, start=toes_start, end=foot_coord[1], line_color=self.COLORS['blue'])
                px_tolerance = max(self.knee_toe_min_px, int(self.knee_toe_offset_ratio * frame_width))
                knee_past_toes = (knee_coord[0] > foot_coord[0] + px_tolerance) if (multiplier == 1) else (knee_coord[0] < foot_coord[0] - px_tolerance)

                # ------------------- Verical Angle calculation --------------
                
                hip_vertical_angle = find_angle(shldr_coord, np.array([hip_coord[0], 0]), hip_coord)
                self._log_angle('back', hip_vertical_angle)
                cv2.ellipse(frame, hip_coord, (30, 30), 
                            angle = 0, startAngle = -90, endAngle = -90+multiplier*hip_vertical_angle, 
                            color = self.COLORS['white'], thickness = 3, lineType = self.linetype)

                short_start_hip = max(0, hip_coord[1] - 32)
                draw_dotted_line(frame, hip_coord, start=short_start_hip, end=hip_coord[1], line_color=self.COLORS['blue'])




                knee_vertical_angle = find_angle(hip_coord, np.array([knee_coord[0], 0]), knee_coord)
                self._log_angle('knee', knee_vertical_angle)
                cv2.ellipse(frame, knee_coord, (20, 20), 
                            angle = 0, startAngle = -90, endAngle = -90-multiplier*knee_vertical_angle, 
                            color = self.COLORS['white'], thickness = 3,  lineType = self.linetype)

                short_start_knee = max(0, knee_coord[1] - 32)
                short_end_knee = min(frame_height - 1, knee_coord[1] + 32)
                draw_dotted_line(frame, knee_coord, start=short_start_knee, end=knee_coord[1], line_color=self.COLORS['blue'])
                draw_dotted_line(frame, knee_coord, start=knee_coord[1], end=short_end_knee, line_color=self.COLORS['blue'])



                ankle_vertical_angle = find_angle(knee_coord, np.array([ankle_coord[0], 0]), ankle_coord)
                self._log_angle('ankle', ankle_vertical_angle)
                cv2.ellipse(frame, ankle_coord, (30, 30),
                            angle = 0, startAngle = -90, endAngle = -90 + multiplier*ankle_vertical_angle,
                            color = self.COLORS['white'], thickness = 3,  lineType=self.linetype)

                short_start_ankle = max(0, ankle_coord[1] - 32)
                draw_dotted_line(frame, ankle_coord, start=short_start_ankle, end=ankle_coord[1], line_color=self.COLORS['blue'])

                start_x = min(heel_coord[0], foot_coord[0])
                end_x = max(heel_coord[0], foot_coord[0])
                draw_dotted_hline(frame, foot_coord[1], start_x, end_x, self.COLORS['blue'])

                # ------------------------------------------------------------
        
                
                # Join landmarks.
                
                cv2.line(frame, shldr_coord, hip_coord, self.COLORS['green'], 4, lineType=self.linetype)
                cv2.line(frame, knee_coord, hip_coord, self.COLORS['green'], 4,  lineType=self.linetype)
                cv2.line(frame, ankle_coord, knee_coord,self.COLORS['green'], 4,  lineType=self.linetype)
                cv2.line(frame, ankle_coord, heel_coord, self.COLORS['green'], 4,  lineType=self.linetype)
                cv2.line(frame, ankle_coord, foot_coord, self.COLORS['green'], 4,  lineType=self.linetype)
                cv2.line(frame, heel_coord, foot_coord, self.COLORS['green'], 4,  lineType=self.linetype)
                cv2.line(frame, shldr_coord, elbow_coord, self.COLORS['green'], 4,  lineType=self.linetype)
                
                # Plot landmark points
                cv2.circle(frame, shldr_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                
                cv2.circle(frame, hip_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, knee_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, ankle_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, heel_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, foot_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, elbow_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                behind_dx = -10 if (multiplier == 1) else 10
                ua_raw = find_angle(elbow_coord, np.array([shldr_coord[0] + behind_dx, shldr_coord[1]]), shldr_coord)
                upper_arm_horiz_angle = min(ua_raw, 180 - ua_raw)
                base_angle = 180 if (multiplier == 1) else 0
                cv2.ellipse(
                    frame,
                    shldr_coord,
                    (25, 25),
                    angle = 0,
                    startAngle = int(base_angle),
                    endAngle = int(base_angle + (-multiplier) * upper_arm_horiz_angle),
                    color = self.COLORS['white'],
                    thickness = 3,
                    lineType = self.linetype
                )
                text_x = shldr_coord[0] - 35 if (multiplier == 1) else shldr_coord[0] + 15
                text_y = shldr_coord[1] - 10
                cv2.putText(frame, str(int(upper_arm_horiz_angle)), (text_x, text_y), self.font, 0.6, self.COLORS['yellow'], 2, lineType=self.linetype)
                

                current_state = self._get_state(int(knee_vertical_angle))
                if not current_state:
                    current_state = self.state_tracker.get('prev_state') or 's1'
                self.state_tracker['curr_state'] = current_state
                self._update_state_sequence(current_state)

                # Log maxima/minima during active squat (state s2 and s3)
                if current_state in ('s2','s3'):
                    self._log_angle('back', hip_vertical_angle)
                    self._log_angle('knee', knee_vertical_angle)
                    self._log_angle('ankle', ankle_vertical_angle)
                    
                    heel_distance_from_ground = abs(heel_coord[1] - foot_coord[1])
                    if heel_distance_from_ground > self.max_heel_distance:
                        self.max_heel_distance = heel_distance_from_ground
                    
                    elbow_flare_angle = upper_arm_horiz_angle
                    if (time.perf_counter() - self._created_at) >= self.headstart_sec:
                        if (self.elbow_flare_min_angle is None) or (elbow_flare_angle < self.elbow_flare_min_angle):
                            self.elbow_flare_min_angle = elbow_flare_angle
                        if elbow_flare_angle < self.elbow_flare_thresh:
                            self.rep_flags['elbow_flaring'] = True
                    
                    if self.state_tracker.get('prev_state') == 's1' and current_state == 's2':
                        self.rep_flags['torso_forward'] = False
                        self.rep_flags['knees_past_toes'] = False
                        self.rep_flags['elbow_flaring'] = False
                        self.elbow_flare_min_angle = None
                        self.max_heel_distance = 0
                        self.event_snapshots['torso_forward'] = None
                        self.event_snapshots['knees_past_toes'] = None
                        self.event_snapshots['heels_lifting'] = None
                        
                    toe_offset_px = max(self.knee_toe_min_px, int(self.knee_toe_offset_ratio * frame_width))
                    shoulder_offset_px = max(self.shoulder_knee_min_px, int(self.shoulder_knee_offset_ratio * frame_width))
                    torso_too_forward_now = (shldr_coord[0] > foot_coord[0] + toe_offset_px) if (multiplier == 1) else (shldr_coord[0] < foot_coord[0] - toe_offset_px)
                    torso_angle_too_forward = hip_vertical_angle >= 45
                    torso_forward_detected = torso_too_forward_now or torso_angle_too_forward
                    knee_past_toes_now = (knee_coord[0] > foot_coord[0] + toe_offset_px) if (multiplier == 1) else (knee_coord[0] < foot_coord[0] - toe_offset_px)
                    
                    self.rep_flags['torso_forward'] = self.rep_flags['torso_forward'] or torso_forward_detected
                    self.rep_flags['knees_past_toes'] = self.rep_flags['knees_past_toes'] or knee_past_toes_now
                    
                    now_ms = int((time.perf_counter() - self._created_at) * 1000)
                    
                    heel_lift_angle_raw_evt = find_angle(foot_coord, np.array([heel_coord[0] + 10, heel_coord[1]]), heel_coord)
                    heel_lift_angle_evt = min(heel_lift_angle_raw_evt, 180 - heel_lift_angle_raw_evt)
                    heels_lifting_now = heel_lift_angle_evt > self.heel_lift_thresh
                    
                    if heels_lifting_now:
                        self.rep_flags['heels_lifting'] = True
                        if current_side == 'left':
                            raw_heel_coord = left_heel_coord
                            raw_foot_coord = left_foot_coord
                        else:
                            raw_heel_coord = right_heel_coord
                            raw_foot_coord = right_foot_coord
                        current_heel_distance = abs(int(raw_heel_coord[1]) - int(raw_foot_coord[1]))
                        snapshot_hl = {
                            'ms': now_ms,
                            'torso_hip_angle': int(hip_vertical_angle),
                            'knee_flexion_angle': int(knee_vertical_angle),
                            'ankle_angle': int(ankle_vertical_angle),
                            'heel_distance': current_heel_distance
                        }
                        current = self.event_snapshots['heels_lifting']
                        if current is None:
                            self.event_snapshots['heels_lifting'] = snapshot_hl
                        else:
                            if current_heel_distance > current['heel_distance']:
                                self.event_snapshots['heels_lifting'] = snapshot_hl
                        
                        if ankle_vertical_angle > 40:
                            self.rep_flags['knees_past_toes'] = True
                            if self.event_snapshots['knees_past_toes'] is None:
                                self.event_snapshots['knees_past_toes'] = snapshot_hl
                            else:
                                current_kpt = self.event_snapshots['knees_past_toes']
                                if snapshot_hl['torso_hip_angle'] > self.snapshot_thresholds['torso_hip_angle']:
                                    if current_kpt['torso_hip_angle'] <= self.snapshot_thresholds['torso_hip_angle'] or snapshot_hl['torso_hip_angle'] > current_kpt['torso_hip_angle']:
                                        self.event_snapshots['knees_past_toes'] = snapshot_hl
                                elif current_kpt['torso_hip_angle'] <= self.snapshot_thresholds['torso_hip_angle']:
                                    if snapshot_hl['torso_hip_angle'] > current_kpt['torso_hip_angle']:
                                        self.event_snapshots['knees_past_toes'] = snapshot_hl
                    
                    if torso_forward_detected:
                        snapshot_tf = {
                            'ms': now_ms,
                            'torso_hip_angle': int(hip_vertical_angle),
                            'knee_flexion_angle': int(knee_vertical_angle),
                            'ankle_angle': int(ankle_vertical_angle),
                            'heel_distance': heel_distance_from_ground
                        }
                        current = self.event_snapshots['torso_forward']
                        if current is None:
                            self.event_snapshots['torso_forward'] = snapshot_tf
                        else:
                            if snapshot_tf['torso_hip_angle'] >= 45:
                                if current['torso_hip_angle'] < 45 or snapshot_tf['torso_hip_angle'] > current['torso_hip_angle']:
                                    self.event_snapshots['torso_forward'] = snapshot_tf
                            elif current['torso_hip_angle'] < 45:
                                if snapshot_tf['torso_hip_angle'] > current['torso_hip_angle']:
                                    self.event_snapshots['torso_forward'] = snapshot_tf
                    
                    if knee_past_toes_now and not (heels_lifting_now and ankle_vertical_angle > 40):
                        snapshot_kpt = {
                            'ms': now_ms,
                            'torso_hip_angle': int(hip_vertical_angle),
                            'knee_flexion_angle': int(knee_vertical_angle),
                            'ankle_angle': int(ankle_vertical_angle),
                            'heel_distance': heel_distance_from_ground
                        }
                        current = self.event_snapshots['knees_past_toes']
                        if current is None:
                            self.event_snapshots['knees_past_toes'] = snapshot_kpt
                        else:
                            if snapshot_kpt['torso_hip_angle'] > self.snapshot_thresholds['torso_hip_angle']:
                                if current['torso_hip_angle'] <= self.snapshot_thresholds['torso_hip_angle'] or snapshot_kpt['torso_hip_angle'] > current['torso_hip_angle']:
                                    self.event_snapshots['knees_past_toes'] = snapshot_kpt
                            elif current['torso_hip_angle'] <= self.snapshot_thresholds['torso_hip_angle']:
                                if snapshot_kpt['torso_hip_angle'] > current['torso_hip_angle']:
                                    self.event_snapshots['knees_past_toes'] = snapshot_kpt
                    if current_state in ('s2','s3'):
                        if torso_forward_detected:
                            draw_text(
                                frame,
                                'TORSO TOO FAR FORWARD',
                                pos=(30, 110),
                                text_color=self.COLORS['yellow'],
                                font_scale=0.9,
                                text_color_bg=(255, 0, 128)
                            )
                        if knee_past_toes_now:
                            draw_text(
                                frame,
                                'KNEE PAST TOES',
                                pos=(30, 140),
                                text_color=self.COLORS['yellow'],
                                font_scale=0.9,
                                text_color_bg=(255, 0, 128)
                            )



                # -------------------------------------- COMPUTE COUNTERS --------------------------------------

                if current_state == 's1':

                    if len(self.state_tracker['state_seq']) == 3 and not self.state_tracker['INCORRECT_POSTURE']:
                        self.state_tracker['SQUAT_COUNT']+=1
                        play_sound = str(self.state_tracker['SQUAT_COUNT'])
                        
                    elif 's2' in self.state_tracker['state_seq'] and len(self.state_tracker['state_seq'])==1:
                        self.state_tracker['IMPROPER_SQUAT']+=1
                        play_sound = 'incorrect'

                    elif self.state_tracker['INCORRECT_POSTURE']:
                        self.state_tracker['IMPROPER_SQUAT']+=1
                        play_sound = 'incorrect'
                        
                    
                    self.state_tracker['state_seq'] = []
                    self.state_tracker['INCORRECT_POSTURE'] = False


                # ----------------------------------------------------------------------------------------------------




                # -------------------------------------- PERFORM FEEDBACK ACTIONS --------------------------------------

                else:
                    if hip_vertical_angle > self.thresholds['HIP_THRESH'][1]:
                        self.state_tracker['DISPLAY_TEXT'][0] = True
                        

                    elif hip_vertical_angle < self.thresholds['HIP_THRESH'][0] and \
                         self.state_tracker['state_seq'].count('s2')==1:
                            self.state_tracker['DISPLAY_TEXT'][1] = True
                        
                                        
                    
                    if self.thresholds['KNEE_THRESH'][0] < knee_vertical_angle < self.thresholds['KNEE_THRESH'][1] and \
                       self.state_tracker['state_seq'].count('s2')==1:
                        self.state_tracker['LOWER_HIPS'] = True


                    elif knee_vertical_angle > self.thresholds['KNEE_THRESH'][2]:
                        self.state_tracker['DISPLAY_TEXT'][3] = True
                        self.state_tracker['INCORRECT_POSTURE'] = True

                    
                    if (ankle_vertical_angle > self.thresholds['ANKLE_THRESH']):
                        self.state_tracker['DISPLAY_TEXT'][2] = True
                        self.state_tracker['INCORRECT_POSTURE'] = True


                # ----------------------------------------------------------------------------------------------------


                
                
                # ----------------------------------- COMPUTE INACTIVITY ---------------------------------------------

                display_inactivity = False
                
                if self.state_tracker['curr_state'] == self.state_tracker['prev_state']:

                    end_time = time.perf_counter()
                    self.state_tracker['INACTIVE_TIME'] += end_time - self.state_tracker['start_inactive_time']
                    self.state_tracker['start_inactive_time'] = end_time

                    if self.state_tracker['INACTIVE_TIME'] >= self.thresholds['INACTIVE_THRESH']:
                        self.state_tracker['SQUAT_COUNT'] = 0
                        self.state_tracker['IMPROPER_SQUAT'] = 0
                        display_inactivity = True

                
                else:
                    
                    self.state_tracker['start_inactive_time'] = time.perf_counter()
                    self.state_tracker['INACTIVE_TIME'] = 0.0

                # -------------------------------------------------------------------------------------------------------
              


                hip_text_coord_x = hip_coord[0] + 10
                knee_text_coord_x = knee_coord[0] + 15
                ankle_text_coord_x = ankle_coord[0] + 10
                heel_text_coord_x = heel_coord[0] + 10

                if self.flip_frame:
                    frame = cv2.flip(frame, 1)
                    hip_text_coord_x = frame_width - hip_coord[0] + 10
                    knee_text_coord_x = frame_width - knee_coord[0] + 15
                    ankle_text_coord_x = frame_width - ankle_coord[0] + 10
                    heel_text_coord_x = frame_width - heel_coord[0] + 10

                
                
                if 's3' in self.state_tracker['state_seq'] or current_state == 's1':
                    self.state_tracker['LOWER_HIPS'] = False

                self.state_tracker['COUNT_FRAMES'][self.state_tracker['DISPLAY_TEXT']]+=1

                frame = self._show_feedback(frame, self.state_tracker['COUNT_FRAMES'], self.FEEDBACK_ID_MAP, self.state_tracker['LOWER_HIPS'])



                if display_inactivity:
                    play_sound = 'reset_counters'
                    self.state_tracker['start_inactive_time'] = time.perf_counter()
                    self.state_tracker['INACTIVE_TIME'] = 0.0
                    if len(self.rep_summaries) > 0:
                        print("[SESSION] Reps Summary:", flush=True)
                        for rep_line in self.rep_summaries:
                            print(rep_line, flush=True)

                
                cv2.putText(frame, str(int(hip_vertical_angle)), (hip_text_coord_x, hip_coord[1]), self.font, 0.6, self.COLORS['yellow'], 2, lineType=self.linetype)
                cv2.putText(frame, str(int(knee_vertical_angle)), (knee_text_coord_x, knee_coord[1]+10), self.font, 0.6, self.COLORS['yellow'], 2, lineType=self.linetype)
                cv2.putText(frame, str(int(ankle_vertical_angle)), (ankle_text_coord_x, ankle_coord[1]), self.font, 0.6, self.COLORS['yellow'], 2, lineType=self.linetype)

                heel_lift_angle_raw = find_angle(foot_coord, np.array([heel_coord[0] + 10, heel_coord[1]]), heel_coord)
                heel_lift_angle = min(heel_lift_angle_raw, 180 - heel_lift_angle_raw)
                self._log_angle('heel', heel_lift_angle)
                cv2.putText(frame, str(int(heel_lift_angle)), (heel_text_coord_x, heel_coord[1]), self.font, 0.6, self.COLORS['yellow'], 2, lineType=self.linetype)

                state_display = {'s1': 'STATE 1', 's2': 'STATE 2', 's3': 'STATE 3'}.get(current_state, 'STATE -')
                draw_text(
                    frame,
                    state_display,
                    pos=(30, 30),
                    text_color=self.COLORS['yellow'],
                    font_scale=1.0,
                    text_color_bg=(0, 0, 0)
                )
 
                # # Visualize heel angle as an arc from horizontal (broken line) to heel->toes direction
                # dx = foot_coord[0] - heel_coord[0]
                # dy = foot_coord[1] - heel_coord[1]
                # start_base = 0 if dx >= 0 else 180
                # end_angle = start_base + (-heel_lift_angle if dy > 0 else heel_lift_angle)
                # cv2.ellipse(frame, heel_coord, (20, 20),
                #             angle = 0, startAngle = int(start_base), endAngle = int(end_angle),
                #             color = self.COLORS['white'], thickness = 3, lineType=self.linetype)

                 
                
                
                self.state_tracker['DISPLAY_TEXT'][self.state_tracker['COUNT_FRAMES'] > self.thresholds['CNT_FRAME_THRESH']] = False
                self.state_tracker['COUNT_FRAMES'][self.state_tracker['COUNT_FRAMES'] > self.thresholds['CNT_FRAME_THRESH']] = 0
                if self.state_tracker.get('prev_state') == 's2' and current_state == 's1':
                    self._finalize_rep()
                if current_state == 's1':
                    self._reset_angle_maxima()
                    self.rep_flags['torso_forward'] = False
                    self.rep_flags['knees_past_toes'] = False
                    self.rep_flags['elbow_flaring'] = False
                    self.rep_flags['heels_lifting'] = False
                    self.elbow_flare_min_angle = None
                    self.event_snapshots['torso_forward'] = None
                    self.event_snapshots['knees_past_toes'] = None
                    self.event_snapshots['heels_lifting'] = None
                    
                self.state_tracker['prev_state'] = current_state
                                  

       
        
        else:

            if self.flip_frame:
                frame = cv2.flip(frame, 1)

            end_time = time.perf_counter()
            self.state_tracker['INACTIVE_TIME'] += end_time - self.state_tracker['start_inactive_time']

            display_inactivity = False

            if self.state_tracker['INACTIVE_TIME'] >= self.thresholds['INACTIVE_THRESH']:
                self.state_tracker['SQUAT_COUNT'] = 0
                self.state_tracker['IMPROPER_SQUAT'] = 0
                # cv2.putText(frame, 'Resetting SQUAT_COUNT due to inactivity!!!', (10, frame_height - 25), self.font, 0.7, self.COLORS['blue'], 2)
                display_inactivity = True

            self.state_tracker['start_inactive_time'] = end_time


            if display_inactivity:
                play_sound = 'reset_counters'
                self.state_tracker['start_inactive_time'] = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] = 0.0
            
            
            
            self.state_tracker['prev_state'] =  None
            self.state_tracker['curr_state'] = None
            self.state_tracker['INACTIVE_TIME_FRONT'] = 0.0
            self.state_tracker['INCORRECT_POSTURE'] = False
            self.state_tracker['DISPLAY_TEXT'] = np.full((5,), False)
            self.state_tracker['COUNT_FRAMES'] = np.zeros((5,), dtype=np.int64)
            self.state_tracker['start_inactive_time_front'] = time.perf_counter()
            
            
            
        return frame, play_sound

                    
