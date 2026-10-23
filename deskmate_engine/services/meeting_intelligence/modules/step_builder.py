import logging
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

class StepBuilder:
    """Consolidates atomic interactions into logical steps with robust deduplication."""
    
    def __init__(self):
        self.current_step_id = 1
        self.current_step_actions = []
        self.last_action_time = 0
        self.steps = []

    def add_action(self, action_event):
        """
        Adds action with strict deduplication to prevent 'Same Image' reports.
        """
        timestamp = action_event["timestamp_raw"]
        
        # 1. Strict Duplicate Check (Spatial + Sequential)
        if self.current_step_actions:
            last = self.current_step_actions[-1]
            
            # Check if same event on same target happened within 3s
            is_same_action = (last["event"] == action_event["event"] and 
                              last["target"] == action_event["target"])
            
            # Check if coordinates are close (same functional button)
            last_c = last.get("cursor")
            curr_c = action_event.get("cursor")
            is_near = False
            if last_c and curr_c:
                dist = ((last_c[0]-curr_c[0])**2 + (last_c[1]-curr_c[1])**2)**0.5
                if dist < 100: is_near = True

            if is_same_action and is_near and (timestamp - last["timestamp_raw"]) < 3.0:
                logger.debug(f"Discarding redundant 'Same Image' action: {action_event['event']}")
                return

        # 2. Step Consolidation Timing
        if self.current_step_actions and (timestamp - self.last_action_time) > 8.0:
            self._finalize_step()

        self.current_step_actions.append(action_event)
        self.last_action_time = timestamp
        
        if len(self.current_step_actions) >= 15:
            self._finalize_step()

    def _finalize_step(self):
        if not self.current_step_actions:
            return

        final_step = self._build_current_step()
        self.steps.append(final_step)
        logger.info(f"Finalized Robust Step {self.current_step_id}: {final_step['summary']}")
        
        self.current_step_id += 1
        self.current_step_actions = []

    def get_step_count(self) -> int:
        """Returns non-destructive count of completed + active steps without finalization."""
        return len(self.steps) + (1 if self.current_step_actions else 0)

    def get_current_steps(self) -> List[Dict[str, Any]]:
        """Return non-destructive snapshot of finalized steps plus current active step."""
        steps_copy = list(self.steps)
        if self.current_step_actions:
            step = self._build_current_step()
            step["actions"] = list(step["actions"])
            steps_copy.append(step)
        return steps_copy

    def _build_current_step(self) -> Dict[str, Any]:
        actions = self.current_step_actions
        primary_action = actions[0]["event"]
        target = actions[0]["target"]
        return {
            "step_id": self.current_step_id,
            "timestamp": actions[0].get("timestamp", "00:00"),
            "summary": f"Step {self.current_step_id}: {primary_action.replace('_', ' ').capitalize()} on {target}",
            "duration": round(actions[-1]["timestamp_raw"] - actions[0]["timestamp_raw"], 2),
            "screenshot_path": next((a.get("asset_path") for a in actions if a.get("asset_path")), ""),
            "actions": actions,
        }

    def get_all_steps(self) -> List[Dict[str, Any]]:
        self._finalize_step()
        return self.steps
