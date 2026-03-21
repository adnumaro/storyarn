# Cross-Scene Flow Continuity

> **Status:** Pending — captured for future planning
> **Priority:** Medium
> **Depends on:** Exploration Variables Epic (Phase 1+2)
> **Last Updated:** 2026-03-20

---

## Problem

In exploration mode, a flow can launch when clicking a pin/zone. But the flow cannot trigger a scene change and continue executing. This limits narrative design:

- NPC says "Let's talk inside the tavern" -> player expects scene to change to interior -> flow should continue with next dialogue
- Player enters a portal zone -> scene transitions -> a flow starts automatically in the new scene
- A cutscene flow moves the player across multiple scenes

Currently, scene navigation (`target_type="scene"`) and flow execution are independent. Navigating to a new scene kills the current flow.

## Desired Behavior

1. A flow instruction/node can trigger a scene transition mid-execution
2. The flow engine pauses, the exploration player navigates to the new scene
3. After the new scene loads, the flow resumes from where it paused
4. Variable state carries across the transition

## Technical Challenges

- `ExplorationLive` is a single LiveView. Navigating to a new scene currently means `push_navigate` to a new URL, which destroys the LiveView and all state.
- Flow execution state (current node, variable state, call stack for subflows) needs to survive the transition.
- The new scene may not have the same pins/zones, so pin-specific variable state needs scoping.

## Possible Approaches

### A: Single LiveView, swap scene data
Keep the same `ExplorationLive` process. Instead of navigating, swap the scene data (background, pins, zones) in-place. The flow engine stays alive.

**Pros:** Simple state management. Flow never stops.
**Cons:** URL doesn't update. Browser back button doesn't work intuitively. Need to load new scene data via context call.

### B: Serialize flow state, navigate, restore
Before navigating, serialize the flow execution state (current node ID, variable map, call stack). Pass it via URL params or session. New `ExplorationLive` instance restores and continues.

**Pros:** Clean navigation. URL updates. Back button works.
**Cons:** Complex serialization. Race conditions. Large state in URL/session.

### C: Persistent flow process
Spawn a separate process for flow execution that outlives the LiveView. New LiveView reconnects to it.

**Pros:** Clean separation. Flow state is authoritative.
**Cons:** Process lifecycle management. What if user closes tab?

## Decision

TBD — needs prototyping. Approach A seems simplest for MVP.
