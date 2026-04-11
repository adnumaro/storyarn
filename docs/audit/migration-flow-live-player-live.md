# Migration: FlowLive.PlayerLive

## Status: not-migrated
## Complexity: medium

## Files

- `lib/storyarn_web/live/flow_live/player_live.ex` -- Main LiveView (500 lines)
- `lib/storyarn_web/live/flow_live/player/components/player_slide.ex` -- Dialogue/slug_line/empty slide rendering (76 lines)
- `lib/storyarn_web/live/flow_live/player/components/player_toolbar.ex` -- Bottom toolbar with nav/mode/restart/exit (83 lines)
- `lib/storyarn_web/live/flow_live/player/components/player_choices.ex` -- Response button list (45 lines)
- `lib/storyarn_web/live/flow_live/player/components/player_outcome.ex` -- End-of-flow outcome screen (75 lines)
- `lib/storyarn_web/live/flow_live/player/player_engine.ex` -- State machine (backend, no migration needed)
- `lib/storyarn_web/live/flow_live/player/slide.ex` -- Slide data builder (backend, no migration needed)

## Current State

This is the only fully V1 LiveView in the project. It renders a full-screen cinematic story player using four HEEx function components:

1. **`player_slide`** -- Renders dialogue (speaker avatar, name, text, stage directions), slug lines (setting, location, time), empty states. Uses `HtmlSanitizer.sanitize_html` for raw HTML content.
2. **`player_toolbar`** -- Bottom bar with back/continue buttons, player/analysis mode toggle, restart, exit link. Uses `<.icon>` from CoreComponents and `<.link>` for navigation.
3. **`player_choices`** -- Renders response buttons with number badges, condition indicators. Filters by validity in player mode.
4. **`player_outcome`** -- End screen with outcome title, tags, stats (steps, choices, variables changed), play-again/back-to-editor actions.

CSS classes are custom `player-*` classes (not DaisyUI), defined in a CSS file. Layout uses `layout: false` (no Phoenix layout wrapper).

The LiveView handles:
- Keyboard shortcuts (via `phx-window-keydown` presumably in JS)
- Cross-flow navigation (jumping between subflows)
- Scene backdrop transitions
- Player session restoration
- Variable state tracking

## What Needs to Change

1. Create a single Vue component `modules/flows/player/FlowPlayer.vue` (or split into sub-components)
2. Port the 4 HEEx function components to Vue:
   - `PlayerSlide.vue` -- slot-based rendering for dialogue/slug_line/empty/outcome
   - `PlayerToolbar.vue` -- bottom toolbar with pushEvent for actions
   - `PlayerChoices.vue` -- response buttons
   - `PlayerOutcome.vue` -- end screen
3. The LiveView render should become a single `<.vue v-component="modules/flows/player/FlowPlayer" ...>` with all state serialized as props
4. Serialize slide data, engine state, player mode, scene backdrop URL as Vue props
5. Move keyboard handling to Vue (already likely handled there for other components)
6. The `player-*` CSS classes can remain as-is since they are custom (not DaisyUI)

## Dependencies

- No new shared components needed -- all UI is self-contained
- `HtmlSanitizer.sanitize_html` output needs to be passed as a prop (already sanitized HTML string)
- Scene backdrop image URL needs serialization
- Lucide icons need to be used via Vue's lucide-vue-next (replacing `<.icon>`)
- Navigation links need to use `useLive().pushEvent` for actions and `v-href` or router for links
