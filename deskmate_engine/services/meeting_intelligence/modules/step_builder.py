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
            
            # Check if same event on same target happened within 2s
            is_same_action = (last["event"] == action_event["event"] and 
                              last["target"] == action_event["target"])
            
            # Check if coordinates are close (same functional button)
            last_c = last.get("cursor")
            curr_c = action_event.get("cursor")
            is_near = False
            if last_c and curr_c:
                dist = ((last_c[0]-curr_c[0])**2 + (last_c[1]-curr_c[1])**2)**0.5
                if dist < 80: is_near = True

            if is_same_action and is_near and (timestamp - last["timestamp_raw"]) < 2.0:
                logger.debug(f"Discarding redundant 'Same Image' action: {action_event['event']}")
                return

            # 2. Step Consolidation & Transition Boundary
            # If the new action is a screen_presentation or milestone, that marks the transition
            # to a new screen state! Finalize previous actions into their own step.
            is_screen_transition = action_event.get("event") == "screen_presentation"
            time_gap = timestamp - self.last_action_time

            # Finalize step if:
            # - A new screen presentation / transition arrived
            # - User paused for > 4.0 seconds (natural boundary)
            # - 4 or more actions accumulated (prevents swallowing multiple UI operations into 1 mega-step)
            if is_screen_transition or time_gap > 4.0 or len(self.current_step_actions) >= 4:
                self._finalize_step()

        self.current_step_actions.append(action_event)
        self.last_action_time = timestamp

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
        first_action = actions[0]
        last_action = actions[-1]

        # Prioritize presentation or specific target over generic 'unclassified'
        pres_action = next((a for a in actions if a.get("event") == "screen_presentation"), None)
        target = first_action.get("target", "UI component")
        for a in actions:
            t = a.get("target", "")
            if t and t not in ("unclassified", "interactive region", "Presentation Milestone", "Presentation Checkpoint"):
                target = t
                break

        primary_action = first_action.get("event", "").replace("_", " ").capitalize()
        if pres_action and pres_action.get("target") not in ("Presentation Milestone", "Presentation Checkpoint", "unclassified"):
            primary_action = "Screen presentation"
            target = pres_action.get("target")

        # Pick the most representative screenshot:
        # Prefer the resulting/latest screenshot (or the presentation screenshot) so the user sees the screen AFTER the transition!
        screenshot = (
            (pres_action.get("asset_path") if pres_action and pres_action.get("asset_path") else None)
            or next((a.get("asset_path") for a in reversed(actions) if a.get("asset_path")), "")
        )

        return {
            "step_id": self.current_step_id,
            "timestamp": first_action.get("timestamp", "00:00"),
            "summary": f"Step {self.current_step_id}: {primary_action} on {target}",
            "duration": round(last_action["timestamp_raw"] - first_action["timestamp_raw"], 2),
            "screenshot_path": screenshot or "",
            "actions": actions,
        }

    def get_all_steps(self) -> List[Dict[str, Any]]:
        self._finalize_step()
        return self.steps
