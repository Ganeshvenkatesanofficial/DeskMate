import logging
from .. import config

logger = logging.getLogger(__name__)

class TemporalTracker:
    """Tracks UI elements across frames based on IoU overlap."""
    
    def __init__(self):
        self.active_tracks = [] # List of dicts: {'id', 'bbox', 'label', 'history', 'disappeared'}
        self.next_id = 0
        self.iou_threshold = config.TRACKER_IOU_THRESHOLD
        self.max_disappeared = config.TRACKER_MAX_DISAPPEARED

    def update(self, detections, current_timestamp):
        """
        detections: list of {'label', 'score', 'box'} where box is absolute [x1, y1, x2, y2]
        """
        if not detections:
            # Handle disappeared objects
            for track in self.active_tracks:
                track["disappeared"] += 1
            self.active_tracks = [t for t in self.active_tracks if t["disappeared"] <= self.max_disappeared]
            return self.active_tracks

        # Match new detections to existing tracks
        new_tracks = []
        matched_indices = set()

        for track in self.active_tracks:
            best_iou = 0
            best_det_idx = -1
            
            for i, det in enumerate(detections):
                if i in matched_indices: continue
                
                iou = self._iou(track["bbox"], det["box"])
                if iou > best_iou:
                    best_iou = iou
                    best_det_idx = i
            
            if best_iou >= self.iou_threshold:
                # Update existing track
                det = detections[best_det_idx]
                track["bbox"] = det["box"]
                track["label"] = det["label"]
                track["history"].append({"timestamp": current_timestamp, "bbox": det["box"]})
                track["disappeared"] = 0
                matched_indices.add(best_det_idx)
                new_tracks.append(track)
            else:
                track["disappeared"] += 1
                if track["disappeared"] <= self.max_disappeared:
                    new_tracks.append(track)

        # Create new tracks for unmatched detections
        for i, det in enumerate(detections):
            if i not in matched_indices:
                new_tracks.append({
                    "id": self.next_id,
                    "bbox": det["box"],
                    "label": det["label"],
                    "history": [{"timestamp": current_timestamp, "bbox": det["box"]}],
                    "disappeared": 0
                })
                self.next_id += 1

        self.active_tracks = new_tracks
        return self.active_tracks

    def _iou(self, box1, box2):
        x1 = max(box1[0], box2[0])
        y1 = max(box1[1], box2[1])
        x2 = min(box1[2], box2[2])
        y2 = min(box1[3], box2[3])

        inter = max(0, x2 - x1) * max(0, y2 - y1)
        area1 = (box1[2] - box1[0]) * (box1[3] - box1[1])
        area2 = (box2[2] - box2[0]) * (box2[3] - box2[1])

        union = area1 + area2 - inter
        return inter / union if union > 0 else 0
