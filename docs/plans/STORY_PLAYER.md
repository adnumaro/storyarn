# Story Player — Interactive Flow Simulation

> **Goal:** Full-screen, cinematic story simulation inspired by articy:draft's Presentation View
>
> **Priority:** HIGH — last major feature before beta (alongside export)
>
> **Dependencies:** Flow engine (done), Debugger (done), Variable system (done)
>
> **Competitive reference:** articy:draft X Presentation View / Simulation Mode
>
> **Last Updated:** February 19, 2026

---

## Overview

The Story Player is a **consumer-facing, full-screen experience** that lets narrative designers play through their interactive stories as a player would. It replaces the existing bare-bones `PreviewComponent` (dialogue-only, no variable evaluation, no condition handling) with a cinematic, PowerPoint-like presentation powered by the existing `Engine` state machine.

**Key insight:** The existing flow debugger already implements ~70% of the logic. The Engine, ConditionEval, InstructionExec, DialogueEvaluator, and all node evaluators are pure functional modules with no UI coupling. The Story Player is a **new UI skin** on top of the same engine, plus journey management and presentation features.

### What articy:draft's Presentation View does

- **Slide-based:** Each node is a fullscreen slide with background, speaker, text, choices
- **Two modes:** Analysis Mode (shows invalid branches in red) vs Player Mode (hides invalid branches)
- **Record Mode:** Choices are recorded as "journey points" in a navigator
- **Journeys:** Saved paths that can be replayed, shared, auto-played
- **Variable tracking:** Evaluates conditions/instructions; allows initial value overrides
- **Auto-play:** Timer-based automatic advancement with configurable speed
- **Navigator:** Left panel listing all visited journey points; click to jump back
- **Language switching:** Switch locale mid-presentation with fallback
- **Audio playback:** Plays voice-over files for dialogue nodes
- **Skip inner content:** Skip scenes to focus on branching points

### What Storyarn's Story Player will do

All of the above, adapted to our architecture, plus:
- **Scene headers:** Cinematic slug line display (INT/EXT + location + time)
- **Stage directions:** Italic action text between dialogue lines
- **Variable interpolation:** `{mc.jaime.health}` renders as the live value
- **Outcome screens:** Styled end-of-story display using exit node tags + color
- **Cross-flow navigation:** Seamless subflow entry/exit with visual transitions
- **Speaker portraits:** Resolved from sheet avatar/banner assets
- **Keyboard navigation:** Space/Enter to advance, number keys for choices, arrow keys for back

---

## Architecture

### Route & LiveView

```
/workspaces/:ws/projects/:proj/flows/:id/play
```

New LiveView: `StoryarnWeb.FlowLive.PlayerLive`

This is a **separate LiveView** from `FlowLive.Show`, not a panel or modal. It uses its own layout (`player` layout) with no sidebar, no header chrome — just the player UI.

The player can also be launched from the flow editor via a "Play" button in the header, which navigates to the player route.

### Module Structure

```
lib/storyarn_web/live/flow_live/
├── player_live.ex                          # Main LiveView (mount, handle_event)
├── player/
│   ├── player_engine.ex                    # Player-specific engine wrapper
│   ├── player_state.ex                     # Extended state for presentation
│   ├── journey.ex                          # Journey data structure
│   ├── components/
│   │   ├── player_slide.ex                 # Main slide renderer
│   │   ├── player_navigator.ex             # Journey navigator (left panel)
│   │   ├── player_toolbar.ex               # Bottom toolbar (controls)
│   │   ├── player_choices.ex               # Response/choice display
│   │   ├── player_outcome.ex               # End-of-story screen
│   │   └── player_variables_overlay.ex     # Optional variables sidebar
│   └── handlers/
│       ├── player_execution_handlers.ex    # Step, choose, auto-play
│       └── player_session_handlers.ex      # Start, stop, journey save/load
```

### Engine Reuse

The Story Player does NOT duplicate the Engine. It wraps it:

```elixir
defmodule StoryarnWeb.FlowLive.Player.PlayerEngine do
  @moduledoc """
  Thin wrapper around the Evaluator.Engine for the Story Player.

  Adds auto-advance logic for non-interactive nodes and
  player-specific state tracking (journey points, slide metadata).
  """

  alias Storyarn.Flows.Evaluator.Engine

  def step_until_interactive(state, nodes, connections) do
    # Steps through non-interactive nodes automatically:
    # entry, hub, scene, condition, instruction, jump
    # Stops at: dialogue (waiting_input OR no-response continue),
    #           exit (finished), error
  end
end
```

### What gets reused directly (no changes needed)

| Module | Used for |
|--------|----------|
| `Evaluator.Engine` | `init/2`, `step/3`, `step_back/1`, `choose_response/3`, `set_variable/3`, `reset/1` |
| `Evaluator.State` | Full state struct |
| `Evaluator.EngineHelpers` | `advance_to`, `follow_output`, `find_connection`, `add_console`, `add_history_entries` |
| `Evaluator.ConditionEval` | Condition evaluation (boolean, switch, per-rule) |
| `Evaluator.InstructionExec` | Variable mutation (all operators) |
| `NodeEvaluators.DialogueEvaluator` | Response condition evaluation, instruction execution, auto-select |
| `NodeEvaluators.ConditionNodeEvaluator` | Boolean and switch mode evaluation |
| `NodeEvaluators.InstructionEvaluator` | Assignment execution |
| `NodeEvaluators.ExitEvaluator` | Terminal, flow_reference, caller_return |
| `DebugExecutionHandlers.build_nodes_map/1` | Build `%{id => node}` map from DB |
| `DebugExecutionHandlers.build_connections/1` | Build connection list from DB |
| `DebugExecutionHandlers.find_entry_node/1` | Find entry node in map |
| `DebugSessionStore` | Cross-flow state persistence (5-min TTL Agent) |
| `Sheets.list_project_variables/1` | Load all project variables |

---

## Player State

Extends the Engine State with presentation-specific fields:

```elixir
defmodule StoryarnWeb.FlowLive.Player.PlayerState do
  @moduledoc """
  Presentation state layered on top of Engine State.
  Tracks journey points, slide settings, and player mode.
  """

  @type journey_point :: %{
    step: integer(),
    node_id: integer(),
    node_type: String.t(),
    flow_id: integer(),
    flow_name: String.t(),
    label: String.t(),           # Display text (speaker + snippet, or node label)
    icon: String.t(),            # Lucide icon name for the navigator
    is_choice: boolean(),        # Was this a branching point?
    chosen_response_id: String.t() | nil,
    chosen_response_text: String.t() | nil,
    invalid: boolean(),          # Did the user pick an invalid (red) branch?
    timestamp: integer()         # Monotonic ms since session start
  }

  @type t :: %__MODULE__{
    engine_state: Storyarn.Flows.Evaluator.State.t(),
    journey: [journey_point()],      # Chronological list of visited points
    player_mode: :player | :analysis, # Player hides invalid; Analysis shows in red
    record_mode: boolean(),           # Whether choices are being recorded
    auto_playing: boolean(),
    auto_play_speed: integer(),       # ms per slide (default 3000)
    show_navigator: boolean(),        # Toggle left panel
    show_variables: boolean(),        # Toggle variables overlay
    current_slide: map() | nil,       # Pre-computed slide data for rendering
    current_flow_name: String.t(),
    locale: String.t(),               # Active locale for content display
    muted: boolean()                  # Audio mute toggle
  }

  defstruct [
    :engine_state,
    :current_slide,
    :current_flow_name,
    journey: [],
    player_mode: :player,
    record_mode: true,
    auto_playing: false,
    auto_play_speed: 3000,
    show_navigator: true,
    show_variables: false,
    locale: "en",
    muted: false
  ]
end
```

---

## Slide System

Each time the engine stops at a presentable node, a **slide** is computed:

```elixir
defmodule StoryarnWeb.FlowLive.Player.Slide do
  @moduledoc """
  Computes the slide data for the current node.
  A slide is a map with all the data needed to render one screen.
  """

  @type t :: %{
    type: :dialogue | :scene | :outcome | :empty,
    # Dialogue fields
    speaker_name: String.t() | nil,
    speaker_avatar_url: String.t() | nil,
    speaker_initials: String.t(),
    text: String.t(),                      # HTML, sanitized + variable-interpolated
    stage_directions: String.t() | nil,
    menu_text: String.t() | nil,
    audio_url: String.t() | nil,
    responses: [response()],
    has_continue: boolean(),               # No responses but has outgoing connection
    # Scene fields
    scene_int_ext: String.t() | nil,
    scene_location: String.t() | nil,
    scene_sub_location: String.t() | nil,
    scene_time_of_day: String.t() | nil,
    scene_description: String.t() | nil,
    # Outcome fields
    outcome_tags: [String.t()],
    outcome_color: String.t(),
    outcome_label: String.t(),
    # Common
    node_id: integer(),
    background_url: String.t() | nil
  }

  @type response :: %{
    id: String.t(),
    text: String.t(),
    valid: boolean(),
    has_condition: boolean(),
    rule_details: [map()]
  }
end
```

### Slide building for each node type

| Node type | Slide behavior |
|-----------|---------------|
| `entry` | Auto-advance (no slide) |
| `dialogue` (no responses) | Show slide with "Continue" button |
| `dialogue` (with responses) | Show slide with response buttons; wait for choice |
| `dialogue` (auto-select: 1 valid) | Show slide briefly (configurable: 0ms = skip, or show with auto-advance) |
| `condition` | Auto-advance (no slide); result logged to journey |
| `instruction` | Auto-advance (no slide); variable changes logged |
| `hub` | Auto-advance (no slide) |
| `jump` | Auto-advance (no slide) |
| `scene` | Show scene header slide briefly (configurable duration), then auto-advance |
| `subflow` | Auto-advance + visual "entering sub-flow" transition |
| `exit` (terminal) | Show outcome slide |
| `exit` (flow_reference) | Auto-advance to target flow |
| `exit` (caller_return) | Auto-advance back to caller |

### Auto-advance logic

The `step_until_interactive/3` function steps through the engine until it reaches a "presentable" stop:

```elixir
def step_until_interactive(engine_state, nodes, connections, journey, opts \\ []) do
  max_auto = opts[:max_auto_steps] || 100  # Safety limit

  do_step(engine_state, nodes, connections, journey, 0, max_auto)
end

defp do_step(state, _nodes, _connections, journey, count, max) when count >= max do
  {:error, state, journey, :auto_step_limit}
end

defp do_step(state, nodes, connections, journey, count, max) do
  case Engine.step(state, nodes, connections) do
    {:ok, new_state} ->
      node = Map.get(nodes, new_state.current_node_id)
      journey = maybe_add_journey_point(journey, node, new_state)

      if interactive_stop?(node) do
        {:ok, new_state, journey}
      else
        do_step(new_state, nodes, connections, journey, count + 1, max)
      end

    {:waiting_input, new_state} ->
      {:waiting_input, new_state, journey}

    {:finished, new_state} ->
      {:finished, new_state, journey}

    {:flow_jump, new_state, flow_id} ->
      {:flow_jump, new_state, journey, flow_id}

    {:flow_return, new_state} ->
      {:flow_return, new_state, journey}

    {:error, new_state, reason} ->
      {:error, new_state, journey, reason}
  end
end

defp interactive_stop?(%{type: "dialogue"}), do: true
defp interactive_stop?(%{type: "scene"}), do: true   # Brief pause
defp interactive_stop?(_), do: false
```

---

## UI Design

### Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ [← Back to editor]                    [🌐 EN ▼] [🔇] [⚙️]      │
├──────────┬───────────────────────────────────────────────────────┤
│          │                                                       │
│ NAVIGATOR│              MAIN SLIDE AREA                          │
│          │                                                       │
│  1. ●    │  ┌─────────────────────────────────────────────┐      │
│  2. ●    │  │                                             │      │
│  3. ●    │  │     [Speaker Avatar]                        │      │
│  4. ● ←  │  │     Speaker Name                            │      │
│  5. ●    │  │                                             │      │
│           │  │     "Dialogue text goes here, with          │      │
│           │  │      variable {mc.jaime.health} rendered    │      │
│           │  │      inline as the actual value."           │      │
│           │  │                                             │      │
│           │  │     ┌─────────────────────────────────┐     │      │
│           │  │     │ 1. Response option one           │     │      │
│           │  │     ├─────────────────────────────────┤     │      │
│           │  │     │ 2. Response option two           │     │      │
│           │  │     ├─────────────────────────────────┤     │      │
│           │  │     │ 3. Response three [?] (red)      │     │      │
│           │  │     └─────────────────────────────────┘     │      │
│           │  │                                             │      │
│           │  └─────────────────────────────────────────────┘      │
│           │                                                       │
├──────────┴───────────────────────────────────────────────────────┤
│  [◀ Back] [▶ Step / Continue]  [⏯ Auto]  [Speed: ━━━●━━]  [🔍]  │
└──────────────────────────────────────────────────────────────────┘
```

### Scene Slide

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                   │
│                                                                   │
│                    ─── ● ───                                      │
│                                                                   │
│               INT. CASTLE THRONE ROOM — NIGHT                     │
│                                                                   │
│         The torches flicker as the king enters alone.             │
│                                                                   │
│                    ─── ● ───                                      │
│                                                                   │
│                                                                   │
│                  [Continue →]  (or auto-advance)                  │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Outcome Slide

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                   │
│                                                                   │
│                        ╔═══════════════╗                          │
│                        ║   THE END     ║                          │
│                        ╚═══════════════╝                          │
│                                                                   │
│                   "The Hero's Sacrifice"                          │
│                                                                   │
│                  [heroic] [bittersweet]                           │
│                                                                   │
│              Steps: 47  |  Choices made: 12                       │
│              Variables changed: 8                                  │
│                                                                   │
│        [↺ Restart]  [← Back to editor]  [💾 Save journey]        │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Navigator Panel (Left)

```
┌──────────────────┐
│ JOURNEY           │
│ ────────────────  │
│                   │
│  ✦ Start          │  (entry node)
│  │                │
│  ◆ INT. Tavern    │  (scene - muted icon)
│  │                │
│  ● Bartender:     │  (dialogue, NPC line)
│  │ "Welcome..."   │
│  │                │
│  ◉ → "Tell me     │  (dialogue, player chose)
│  │    about..."   │
│  │                │
│  ⚡ health += 10  │  (instruction - auto icon)
│  │                │
│  ● Guard:         │  (current position ←)
│  │ "Halt!"        │
│                   │
│ ────────────────  │
│ Step 7 of 7       │
│ [💾 Save journey] │
└──────────────────┘
```

Click any journey point to jump back to that position (using `step_back` repeatedly or snapshot restore).

### Variables Overlay (Optional, toggleable)

```
┌──────────────────────────────────┐
│ VARIABLES            [× Close]   │
│ ──────────────────────────────── │
│ 🔍 Filter...                     │
│ ☐ Changed only                   │
│                                  │
│ mc.jaime.health     100 → 90     │
│ mc.jaime.mood       neutral      │
│ global.gold         50 → 60      │
│ quest.started       false → true │
│                                  │
│ [Override values...]             │
└──────────────────────────────────┘
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` / `Enter` | Continue / Advance |
| `1`-`9` | Select response by number |
| `←` / `Backspace` | Go back one step |
| `→` | Same as Continue |
| `Escape` | Exit player (back to editor) |
| `N` | Toggle navigator panel |
| `V` | Toggle variables overlay |
| `M` | Toggle mute |
| `P` | Toggle player/analysis mode |
| `A` | Toggle auto-play |

---

## Analysis Mode vs Player Mode

| Aspect | Player Mode | Analysis Mode |
|--------|-------------|---------------|
| Invalid responses | Hidden | Shown with red styling + ✗ icon |
| Condition details | Hidden | Shown as tooltip on invalid responses |
| Response condition badge | Hidden | Shown as `[?]` badge |
| Variable changes | Hidden | Shown as toast notification on auto-advance |
| Condition node outcome | Hidden | Shown as brief flash ("Condition → true") |
| Instruction node effect | Hidden | Shown as brief flash ("health: 100 → 90") |

Toggle via toolbar button or `P` key. Default: Player Mode.

---

## Audio System

Dialogue nodes have `audio_asset_id`. When present:

1. Resolve asset URL from `Assets.get_asset!/1`
2. Play via HTML5 `<audio>` element (managed by a JS hook)
3. Auto-advance when audio finishes (if auto-play enabled and no responses)
4. Visual indicator: speaker icon pulses while audio plays
5. Mute button in toolbar (persists via localStorage)

```elixir
# In slide building
defp resolve_audio_url(nil, _project_id), do: nil
defp resolve_audio_url(asset_id, project_id) do
  case Assets.get_asset(project_id, asset_id) do
    nil -> nil
    asset -> Assets.asset_url(asset)
  end
end
```

JS Hook:

```javascript
// hooks/player_audio.js
export const PlayerAudio = {
  mounted() {
    this.audio = this.el.querySelector("audio");
    this.handleEvent("play_audio", ({ url }) => {
      if (this.audio && url) {
        this.audio.src = url;
        this.audio.play().catch(() => {}); // Autoplay policy
      }
    });
    this.handleEvent("stop_audio", () => {
      if (this.audio) { this.audio.pause(); this.audio.currentTime = 0; }
    });
  }
};
```

---

## Speaker Resolution

Currently the `PreviewComponent` only resolves speaker name. The player needs:

```elixir
defp resolve_speaker(nil, _sheets_map, _project_id), do: %{name: nil, avatar_url: nil, initials: "?"}

defp resolve_speaker(sheet_id, sheets_map, project_id) do
  sheet = sheets_map[to_string(sheet_id)] || load_sheet(sheet_id, project_id)

  %{
    name: sheet && sheet.name,
    avatar_url: sheet && sheet.avatar_asset_id && Assets.asset_url(sheet.avatar_asset_id),
    initials: speaker_initials(sheet && sheet.name)
  }
end
```

---

## Variable Interpolation

Replace the cosmetic badge interpolation with live value resolution:

```elixir
defp interpolate_variables(text, variables) when is_binary(text) do
  Regex.replace(~r/\{([a-zA-Z0-9_.]+)\}/, text, fn _full, var_ref ->
    case Map.get(variables, var_ref) do
      %{value: value} ->
        ~s(<span class="player-var" title="#{var_ref}">#{format_display_value(value)}</span>)
      nil ->
        ~s(<span class="player-var player-var-unknown" title="#{var_ref} (unknown)">[#{var_ref}]</span>)
    end
  end)
end
```

---

## Journey System

### Data Structure

```elixir
defmodule StoryarnWeb.FlowLive.Player.Journey do
  @type t :: %__MODULE__{
    id: String.t() | nil,       # nil for temporary journeys
    name: String.t(),
    flow_id: integer(),
    project_id: integer(),
    points: [PlayerState.journey_point()],
    initial_variable_overrides: %{String.t() => any()},
    settings: %{
      auto_play_speed: integer(),
      player_mode: :player | :analysis,
      locale: String.t()
    },
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
end
```

### Saving Journeys (Phase 2)

Journeys can be saved to the database for replay:

```elixir
# Migration: create_flow_journeys
create table(:flow_journeys) do
  add :flow_id, references(:flows, on_delete: :delete_all), null: false
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :points, :jsonb, default: "[]"
  add :variable_overrides, :jsonb, default: "{}"
  add :settings, :jsonb, default: "{}"
  timestamps()
end

create index(:flow_journeys, [:flow_id])
create index(:flow_journeys, [:user_id])
```

### Journey Replay

When replaying a saved journey with record mode OFF:
1. The engine auto-selects the recorded choice at each branching point
2. Navigation is restricted to the recorded path
3. Content reflects current node data (text updates since recording are visible)
4. Auto-play steps through the journey automatically at the configured speed
5. User can re-enable record mode to deviate from the recorded path

---

## Cross-Flow Navigation

Reuses the existing `DebugSessionStore` pattern:

1. When engine returns `{:flow_jump, state, target_flow_id}`:
   - Push current flow context to `Engine.push_flow_context/5`
   - Store player assigns in `DebugSessionStore` (rename to `SessionStore` or reuse)
   - `push_navigate` to `/flows/:target_flow_id/play`
   - New mount detects stored state, restores, continues

2. When engine returns `{:flow_return, state}`:
   - Pop context from call stack
   - Store + navigate back to the caller flow's player route

The player shows a breadcrumb trail when inside a sub-flow:

```
Main Quest → Side Quest: Tavern Brawl → (current)
```

---

## Localization Support (Phase 3)

If the project has localization data:
1. Language selector dropdown in the toolbar
2. Switching locale reloads node text from the localization table
3. Fallback to primary language if translation missing
4. Locale persists across the session (stored in player state)

This requires:
- Loading localized text for dialogue nodes via `Localizations.get_translation/3`
- Applying locale to the slide building step
- UI indicator for missing translations (fallback shown with warning icon)

---

## Implementation Phases

### Phase 1: Core Player (MVP)

**Goal:** Functional full-screen player with engine-powered execution

**Files to create:**
- `lib/storyarn_web/live/flow_live/player_live.ex` — Main LiveView
- `lib/storyarn_web/live/flow_live/player/player_engine.ex` — Engine wrapper with `step_until_interactive`
- `lib/storyarn_web/live/flow_live/player/slide.ex` — Slide builder
- `lib/storyarn_web/live/flow_live/player/components/player_slide.ex` — Slide renderer
- `lib/storyarn_web/live/flow_live/player/components/player_choices.ex` — Response buttons
- `lib/storyarn_web/live/flow_live/player/components/player_toolbar.ex` — Bottom controls
- `lib/storyarn_web/live/flow_live/player/components/player_outcome.ex` — End screen
- `assets/css/player.css` — Player-specific styles

**Features:**
- [ ] New route `/flows/:id/play` in router
- [ ] New player layout (fullscreen, no app chrome)
- [ ] Mount: load flow, nodes, connections, variables, init engine
- [ ] `step_until_interactive`: auto-advance through non-interactive nodes
- [ ] Dialogue slide: speaker name/initials, sanitized HTML text, response buttons
- [ ] Scene slide: INT/EXT + location + time of day + description
- [ ] Stage directions: rendered as italic text below/above dialogue
- [ ] Continue button for dialogues without responses
- [ ] Response selection: evaluate conditions, follow correct connection
- [ ] Outcome slide: exit node label, tags, color, restart button
- [ ] Back button (step_back from engine snapshots)
- [ ] Player mode (hide invalid responses) vs Analysis mode (show in red)
- [ ] Keyboard shortcuts (Space, Enter, 1-9, ←, Escape)
- [ ] Variable interpolation in dialogue text (`{var.name}` → live value)
- [ ] "Back to editor" link
- [ ] "Play" button in flow editor header

**What gets deleted:**
- The existing `PreviewComponent` can be kept as-is (it's a quick-peek modal). The new player is a separate, full-featured experience.

---

### Phase 2: Navigator + Journeys

**Goal:** Journey tracking, navigator panel, save/replay

**Files to create:**
- `lib/storyarn_web/live/flow_live/player/journey.ex` — Journey struct
- `lib/storyarn_web/live/flow_live/player/components/player_navigator.ex` — Navigator panel
- `lib/storyarn/flows/flow_journey.ex` — Schema (if DB persistence)
- `priv/repo/migrations/..._create_flow_journeys.exs` — Migration

**Features:**
- [ ] Navigator panel (left side, toggleable with `N`)
- [ ] Journey point tracking: log each presentable stop with metadata
- [ ] Click journey point to jump back (restore from snapshot)
- [ ] Record mode toggle (on = record choices; off = locked to recorded path)
- [ ] Save journey to database (name, points, variable overrides, settings)
- [ ] Load saved journey and replay
- [ ] Journey list (per flow, per user)
- [ ] Delete journey
- [ ] Auto-play: timer-based advancement with speed slider
- [ ] Auto-play pauses at choice points (waiting_input)
- [ ] Configurable scene slide duration (0 = skip, 1000-5000ms)

---

### Phase 3: Audio, Portraits & Polish

**Goal:** Full cinematic experience

**Files to create:**
- `assets/js/hooks/player_audio.js` — Audio playback hook
- `lib/storyarn_web/live/flow_live/player/components/player_variables_overlay.ex` — Variables panel

**Features:**
- [ ] Audio playback for dialogue nodes with `audio_asset_id`
- [ ] Mute toggle (persisted to localStorage)
- [ ] Speaker portrait resolution (sheet avatar asset)
- [ ] Speaker portrait display (circular image, fallback to initials)
- [ ] Variables overlay panel (toggleable with `V`)
- [ ] Variable override for initial values (testing scenarios)
- [ ] Slide transitions (fade between slides, configurable)
- [ ] Background image per slide (from sheet banner or node preview)
- [ ] Cross-flow navigation with visual transition ("Entering: Quest Name")
- [ ] Cross-flow breadcrumb trail
- [ ] Locale switching (if localization data exists)
- [ ] Missing translation indicator
- [ ] Print/share journey as formatted text report

---

### Phase 4: Advanced Features (Post-Beta)

**Features (deferred):**
- [ ] Journey comparison (side-by-side diff of two journey paths)
- [ ] Journey export (share as link, embed in docs)
- [ ] Statistics dashboard (choice distribution across all saved journeys)
- [ ] Conditional breakpoints in player (analysis mode only)
- [ ] "Skip to next choice" button (fast-forward through linear sections)
- [ ] Background music/ambience (separate from dialogue VO)
- [ ] Fullscreen mode (browser fullscreen API)
- [ ] Custom slide themes (font, colors, backgrounds per project)
- [ ] Presentation mode (projector-friendly, larger text)

---

## Gettext Entries Needed

New domain: `"player"` (or extend `"flows"`)

```
# Player UI
"Story Player"
"Continue"
"Back"
"Back to editor"
"Restart"
"Save journey"
"Load journey"
"Navigator"
"Variables"
"Analysis Mode"
"Player Mode"
"Auto-play"
"Speed"
"Mute"
"Unmute"

# Scene
"INT."
"EXT."

# Outcome
"The End"
"Steps: %{count}"
"Choices made: %{count}"
"Variables changed: %{count}"
"Restart story"
"Save this journey"

# Journey
"Journey saved"
"Journey loaded"
"Journey name"
"Unnamed journey"
"Saved journeys"
"No saved journeys"
"Delete journey"
"Are you sure you want to delete this journey?"

# Errors
"No entry node found"
"Execution limit reached"
"Flow not found"

# Analysis mode
"Condition failed"
"Response unavailable"
"Variable changed: %{var} = %{value}"
```

---

## CSS Architecture

Player styles live in `assets/css/player.css`, imported in `app.css`:

```css
/* Player layout */
.player-container { /* fullscreen flex container */ }
.player-navigator { /* left panel, collapsible */ }
.player-slide { /* center content area */ }
.player-toolbar { /* bottom bar */ }

/* Slide types */
.player-slide-dialogue { /* speaker + text + responses */ }
.player-slide-scene { /* cinematic scene header */ }
.player-slide-outcome { /* end screen */ }

/* Responses */
.player-response { /* choice button */ }
.player-response-invalid { /* red styling for analysis mode */ }
.player-response-selected { /* highlight after selection */ }

/* Navigator */
.player-journey-point { /* single point in navigator */ }
.player-journey-point-current { /* current position marker */ }
.player-journey-point-choice { /* branching point indicator */ }

/* Variables */
.player-var { /* inline variable in text */ }
.player-var-changed { /* flashes when value changes */ }
.player-var-unknown { /* unresolved variable */ }

/* Transitions */
.player-slide-enter { /* fade-in animation */ }
.player-slide-exit { /* fade-out animation */ }
```

---

## Testing Strategy

### Unit Tests

```
test/storyarn_web/live/flow_live/player/
├── player_engine_test.exs    # step_until_interactive, auto-advance logic
├── slide_test.exs            # Slide building for each node type
└── journey_test.exs          # Journey point tracking, save/load
```

Key test scenarios:
1. Dialogue with 3 responses, 1 invalid → player mode hides 1, analysis shows all
2. Chain: entry → instruction → condition → dialogue → exit (auto-advances through non-interactive)
3. Cross-flow: subflow → enters child flow → exit(caller_return) → returns
4. Variable interpolation: `{mc.health}` resolves to current value
5. Step back: undo through auto-advanced nodes
6. Scene node: produces scene slide with correct INT/EXT + location
7. Exit node: produces outcome slide with tags and color
8. Max steps guard: doesn't infinite-loop on cyclic graphs

### Integration Tests (LiveView)

```
test/storyarn_web/live/flow_live/player_live_test.exs
```

Key scenarios:
1. Mount player → shows first dialogue slide
2. Select response → advances to next dialogue
3. Back button → returns to previous slide
4. Analysis mode → shows invalid responses in red
5. Outcome screen → shows exit tags and restart button
6. Keyboard shortcuts work (simulate keydown events)

---

## Migration Path

1. **Phase 1** can ship independently — no schema changes, no breaking changes
2. **Phase 2** adds one migration (`flow_journeys`) — optional, player works without saved journeys
3. **Phase 3** adds no schema changes — uses existing `audio_asset_id` and `avatar_asset_id`
4. Existing `PreviewComponent` remains untouched (deprecated later, not removed)

---

## Performance Considerations

- **Slides are computed on mount and on step** — no per-render computation
- **Auto-advance batching:** `step_until_interactive` executes multiple engine steps in one server round-trip (not one WS message per auto-advanced node)
- **Node map is in-memory** for the current flow (same pattern as debugger)
- **Variables map is in-memory** (no DB reads during execution)
- **Journey points are lightweight** (just metadata, not full snapshots)
- **Snapshot stack** (for step_back) is capped at 50 by the engine
- **Cross-flow:** uses the same Agent-based store with 5-min TTL

---

## Comparison: Storyarn Story Player vs articy:draft Presentation View

| Feature | articy:draft | Storyarn (planned) |
|---------|-------------|-------------------|
| Slide-based presentation | ✅ | ✅ Phase 1 |
| Condition/instruction evaluation | ✅ | ✅ Phase 1 (engine reuse) |
| Player vs Analysis mode | ✅ | ✅ Phase 1 |
| Record mode + journeys | ✅ | ✅ Phase 2 |
| Navigator panel | ✅ | ✅ Phase 2 |
| Auto-play | ✅ | ✅ Phase 2 |
| Journey save/load | ✅ | ✅ Phase 2 |
| Voice-over playback | ✅ | ✅ Phase 3 |
| Language switching | ✅ | ✅ Phase 3 |
| Variable overrides | ✅ | ✅ Phase 3 |
| Scene headers (cinematic) | ❌ | ✅ Phase 1 (unique to Storyarn) |
| Stage directions | ❌ | ✅ Phase 1 (unique to Storyarn) |
| Variable interpolation in text | ❌ | ✅ Phase 1 (unique to Storyarn) |
| Speaker portraits | Partial | ✅ Phase 3 |
| Outcome screen with tags | ❌ | ✅ Phase 1 (unique to Storyarn) |
| Cross-flow (subflows) | ❌ (flat flows) | ✅ Phase 1 (engine reuse) |
| Keyboard shortcuts | ❌ | ✅ Phase 1 |
| Step back (undo) | Via navigator | ✅ Phase 1 (snapshot-based, instant) |
| Slide backgrounds | ✅ (per-slide) | ✅ Phase 3 |
| Custom functions prompt | ✅ | N/A (no custom functions) |

---

*This document will be updated as implementation progresses.*
