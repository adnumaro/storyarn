# Dialogue Node Enhancement Plan

> **Objective**: Enhance Storyarn's dialogue node to match the feature set of articy:draft and Arcweave, the industry-leading narrative design tools.

## Current State vs Target State

### Current Implementation
```elixir
%{
  "speaker_page_id" => nil,
  "text" => "",
  "responses" => []
}
```

### Target Implementation
```elixir
%{
  # === SPEAKER ===
  "speaker_page_id" => nil,           # Reference to character Page

  # === TEXT FIELDS (articy-style) ===
  "text" => "",                       # Full dialogue text (VO/subtitles)
  "menu_text" => "",                  # Short version for choice menus
  "stage_directions" => "",           # Voice acting notes, emphasis, mood

  # === VISUAL ===
  "color" => "default",               # Node color for organization
  "cover_asset_id" => nil,            # Scene/portrait image (Asset reference)
  "audio_asset_id" => nil,            # Attached audio file (Asset reference)

  # === TECHNICAL ===
  "technical_id" => "",               # Export identifier (auto-generated or custom)
  "external_id" => "",                # Localization tool ID

  # === LOGIC ===
  "input_condition" => "",            # Condition to enter this node
  "output_instruction" => "",         # Action when leaving (set variables, etc.)

  # === TEMPLATES ===
  "template_id" => nil,               # Reference to DialogueTemplate
  "template_properties" => %{},       # Custom properties from template

  # === RESPONSES (enhanced) ===
  "responses" => [
    %{
      "id" => "uuid",
      "text" => "",                   # Full response text
      "menu_text" => "",              # Short version for UI
      "condition" => "",              # Visibility condition
      "instruction" => ""             # Action when selected
    }
  ]
}
```

---

## Implementation Phases

### Phase 1: Core Dialogue Enhancement
**Priority: Essential | Effort: Medium-High**

This phase transforms the basic dialogue node into a professional-grade editing experience with:
- Dynamic node header (reflects speaker)
- New text fields (stage directions, menu text)
- Dual editing modes (sidebar + screenplay fullscreen)

---

#### 1.1 Dynamic Node Header

When a speaker is selected, the node header shows the speaker's identity while keeping the current dialogue color.

**Default State (no speaker):**
```
┌─────────────────────────────┐
│ 💬 Dialogue                 │  ← Default icon + "Dialogue" label
│ (dialogue color - current)  │
└─────────────────────────────┘
```

**With Speaker Selected:**
```
┌─────────────────────────────┐
│ [Avatar] Old Merchant       │  ← Speaker's avatar + name
│ (dialogue color - same)     │  ← Keep current header color
└─────────────────────────────┘
```

**Data Source (from Speaker's Page):**
- `avatar_asset_id` → Node header icon (circular, small)
- `name` → Node header title (replaces "Dialogue")
- Color remains the default dialogue node color

**Implementation:**

1. **Pass speaker page data to canvas nodes:**
   - The `pagesMap` already exists in `storyarn_node.js`
   - Ensure it includes `avatar_url` for each page

2. **Update node rendering logic:**
   ```javascript
   // storyarn_node.js
   if (nodeType === "dialogue" && speakerPage) {
     // Use speaker's avatar and name, keep dialogue color
     headerIcon = speakerPage.avatar_url || config.icon;
     headerTitle = speakerPage.name;
     headerBackground = config.color;  // Keep default dialogue color
   } else {
     // Default dialogue appearance
     headerIcon = config.icon;
     headerTitle = config.label;
     headerBackground = config.color;
   }
   ```

> **Future Feature:** Header customization (banner background, speaker colors) - see FUTURE_FEATURES.md

---

#### 1.2 Text Fields

Add two new text fields following the articy:draft pattern.

**Stage Directions (Acotaciones)**

Purpose: Instructions for voice actors, animators, or documentation of emotional intent.

```
Examples:
- (whispering, looking around nervously)
- (sarcastic, rolling eyes)
- (shouting with anger)
- (long pause before speaking)
- (interrupting)
```

**Characteristics:**
- Plain text (no rich formatting needed)
- Displayed in italics, dimmed color
- Shown on node canvas below speaker name
- Common in VO scripts and screenplay formats

**Menu Text**

Purpose: Short version of dialogue for space-constrained UI (choice wheels, mobile, etc.)

```
Full Text: "I've been waiting for you for three long days, and I was starting to think you'd never show up."
Menu Text: "I've been waiting"
```

**Characteristics:**
- Plain text, max ~50 characters recommended
- Optional - if empty, game uses full text
- Collapsible in sidebar (hidden by default)
- Can be AI-generated in future (see FUTURE_FEATURES.md)

**Updated Data Structure:**
```elixir
def default_node_data("dialogue") do
  %{
    "speaker_page_id" => nil,
    "stage_directions" => "",    # NEW
    "text" => "",
    "menu_text" => "",           # NEW
    "responses" => []
  }
end
```

---

#### 1.3 Dual Editing Modes

Two ways to edit dialogue nodes, complementary to each other.

**Mode A: Sidebar Panel (Current + Enhanced)**

Activated by: **Single click** on node

```
┌─────────────────────────────────────┐
│ [Avatar] Old Merchant            ✕ │  ← Dynamic header
├─────────────────────────────────────┤
│                                     │
│ Speaker        [Old Merchant ▼]     │
│                                     │
│ Stage          ┌───────────────────┐│
│ Directions     │ (whispering)      ││
│                └───────────────────┘│
│                                     │
│ Text           ┌───────────────────┐│
│                │ [Tiptap editor]   ││
│                │                   ││
│                └───────────────────┘│
│                                     │
│ ▶ Menu Text    (click to expand)   │  ← Collapsible
│                                     │
│ ─────────── Responses ────────────  │
│ [Response list...]                  │
│                                     │
├─────────────────────────────────────┤
│ [📜 Open Screenplay Editor]         │  ← Button to switch
│ [▶️ Preview] [🗑️ Delete]            │
└─────────────────────────────────────┘
```

**Mode B: Screenplay Editor (NEW - Fullscreen)**

Activated by: **Double click** on node OR button in sidebar

Professional screenplay format for comfortable long-form writing.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                                                               [✕ Close]    │
│                                                    [📋 Open Sidebar]       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│                                                                            │
│                              OLD MERCHANT                                  │
│                         (leaning forward, quiet)                           │
│                                                                            │
│                  I've got something special for you today,                 │
│                  traveler. Something that fell off the back                │
│                  of a royal carriage, if you catch my meaning.             │
│                                                                            │
│                                                                            │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                            │
│  RESPONSES                                                                 │
│                                                                            │
│    1. "Show me what you have"                                              │
│       └─ Condition: gold > 100                                             │
│                                                                            │
│    2. "I'm not interested in stolen goods"                                 │
│       └─ (no condition)                                                    │
│                                                                            │
│    3. "Who are you, anyway?"                                               │
│       └─ (no condition)                                                    │
│                                                                            │
│                                                                            │
├────────────────────────────────────────────────────────────────────────────┤
│  Speaker: Old Merchant │ Words: 24 │ Menu Text: "Merchant greeting"        │
│                                                                            │
│  [Tab] Stage Directions  [Enter] New line  [Esc] Close                     │
└────────────────────────────────────────────────────────────────────────────┘
```

**Screenplay Format Rules:**

| Element | Format | Keyboard |
|---------|--------|----------|
| Speaker Name | CENTERED, UPPERCASE | Auto (from selection) |
| Stage Directions | Centered, (parentheses), italic | `Tab` or type `(` |
| Dialogue Text | Centered, limited width (~60 chars) | `Enter` after stage directions |
| Responses | Left-aligned list | Below main dialogue |

**Interaction Flow:**

```
Canvas Node                    Sidebar                     Screenplay
    │                            │                            │
    │── single click ──────────→ │                            │
    │                            │                            │
    │── double click ─────────────────────────────────────────→│
    │                            │                            │
    │                            │── click "Screenplay" ──────→│
    │                            │                            │
    │                            │←── click "Sidebar" ────────│
    │                            │                            │
    │←── click outside ──────────│←── Esc or ✕ ───────────────│
```

**Only One Open:**
- Opening screenplay closes sidebar
- Opening sidebar closes screenplay
- Clicking outside closes both

**Implementation:**

1. **LiveView State:**
   ```elixir
   # In socket assigns
   :editing_mode  # nil | :sidebar | :screenplay
   :editing_node_id
   ```

2. **Events:**
   ```elixir
   def handle_event("node_click", %{"id" => id}, socket) do
     {:noreply, assign(socket, editing_mode: :sidebar, editing_node_id: id)}
   end

   def handle_event("node_double_click", %{"id" => id}, socket) do
     {:noreply, assign(socket, editing_mode: :screenplay, editing_node_id: id)}
   end

   def handle_event("open_screenplay", _, socket) do
     {:noreply, assign(socket, editing_mode: :screenplay)}
   end

   def handle_event("open_sidebar", _, socket) do
     {:noreply, assign(socket, editing_mode: :sidebar)}
   end

   def handle_event("close_editor", _, socket) do
     {:noreply, assign(socket, editing_mode: nil, editing_node_id: nil)}
   end
   ```

3. **New Component:**
   ```
   lib/storyarn_web/live/flow_live/components/screenplay_editor.ex
   ```

4. **JS Hook for Screenplay:**
   ```
   assets/js/hooks/screenplay_editor.js
   ```
   - Handle `Tab` for stage directions mode
   - Handle `Enter` for switching to dialogue
   - Handle `Esc` to close
   - Auto-format text as user types

---

#### 1.4 Node Canvas Display (Compact)

Updated node appearance with speaker integration:

**Without Speaker:**
```
┌─────────────────────────────┐
│ 💬 Dialogue                 │
├─────────────────────────────┤
│ "Click to add dialogue..."  │
├─────────────────────────────┤
│                         ──○ │
└─────────────────────────────┘
```

**With Speaker + Content:**
```
┌─────────────────────────────┐
│ [🧙] Old Merchant           │  ← Avatar + name (keeps dialogue color)
├─────────────────────────────┤
│ (whispering)                │  ← Stage directions (italic, dim)
│ "I've got something..."     │  ← Text preview (truncated)
├─────────────────────────────┤
│              "Show me"  ──○ │  ← Responses as outputs
│         "Not interested" ──○ │
└─────────────────────────────┘
```

---

#### 1.5 Files to Modify

**Backend (Elixir):**
| File | Changes |
|------|---------|
| `lib/storyarn_web/live/flow_live/components/node_type_helpers.ex` | Update `default_node_data/1` |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | Add stage_directions, menu_text fields, screenplay button |
| `lib/storyarn_web/live/flow_live/show.ex` | Add editing_mode state, handle double-click event |
| `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` | **NEW** - Fullscreen screenplay component |

**Frontend (JavaScript):**
| File | Changes |
|------|---------|
| `assets/js/hooks/flow_canvas/components/storyarn_node.js` | Dynamic header, stage directions display |
| `assets/js/hooks/flow_canvas/node_config.js` | Pass speaker data to nodes |
| `assets/js/hooks/screenplay_editor.js` | **NEW** - Screenplay formatting hook |

**Styles (CSS):**
| File | Changes |
|------|---------|
| `assets/css/app.css` | Screenplay editor styles, node header with banner |

---

#### 1.6 Tasks

**Dynamic Header:** ✅ COMPLETED
- [x] Update `storyarn_node.js` to use speaker avatar/name when available
- [x] Ensure `pagesMap` includes `avatar_url` for each page
- [x] Fallback to default "Dialogue" icon/label when no speaker
- [x] Keep current dialogue header color (no banner for now)

**Text Fields:** ✅ COMPLETED
- [x] Update `default_node_data/1` with `stage_directions` and `menu_text`
- [x] Add stage directions textarea to properties panel
- [x] Add collapsible menu text field to properties panel
- [x] Display stage directions on node canvas (italic, dimmed)

**Dual Editing Modes:** ✅ COMPLETED
- [x] Add `editing_mode` state to FlowLive.Show
- [x] Handle single click → sidebar
- [x] Handle double click → screenplay (via JS hook push_event)
- [x] Create `screenplay_editor.ex` component (now a LiveComponent for reusability)
- [x] Create `screenplay_editor.js` hook
- [x] Add "Open Screenplay" button to sidebar
- [x] Add "Open Sidebar" button to screenplay
- [x] Ensure mutual exclusivity (only one open)
- [x] Handle Esc to close screenplay

**Testing:** ✅ COMPLETED
- [x] New dialogue nodes have stage_directions and menu_text fields
- [x] Existing dialogues continue to work (backward compatible)
- [x] Single click opens sidebar
- [x] Double click opens screenplay editor
- [x] Switching between modes preserves data
- [x] Speaker data reflects in node header

**Bonus:**
- [x] ScreenplayEditor converted to LiveComponent for reusability outside Flows

---

### Phase 2: Visual Customization
**Priority: Essential | Effort: Medium**

Add visual assets for better organization.

#### 2.1 Node Colors - DEFERRED

> **Note**: Node colors will be managed through the speaker Page's color property.
> See FUTURE_FEATURES.md for the speaker color integration plan.

#### 2.2 Cover Image - DEFERRED

> **Note**: Cover images are a "nice to have" feature.
> See FUTURE_FEATURES.md for future implementation.

#### 2.3 Audio Asset ✅ COMPLETED

Attach audio Assets (VO, ambient sound) to dialogue nodes.

**Properties Panel**:
- Audio asset dropdown selector in collapsible "Audio" section
- HTML5 audio preview player when audio is selected
- Badge indicator showing audio is attached

**Node Rendering**:
- Small audio icon (🔊) in node header when audio is attached

**Implementation**:
- `audio_asset_id` field added to dialogue node data
- Audio assets loaded from project assets (filtered by `content_type: "audio/"`)
- Preview player with native HTML5 `<audio>` controls

#### Tasks
- [x] ~~Add color field~~ - Deferred to speaker Page colors
- [x] ~~Create color selector~~ - Deferred
- [x] ~~Update node rendering for color~~ - Deferred
- [x] ~~Add cover_asset_id field~~ - Deferred to FUTURE_FEATURES.md
- [x] ~~Create asset picker for images~~ - Deferred
- [x] Add audio_asset_id field to dialogue data structure
- [x] Add audio asset dropdown to properties panel
- [x] Add audio preview functionality (HTML5 audio player)
- [x] Add audio indicator icon on canvas node

---

### Phase 3: Technical Identifiers
**Priority: Important | Effort: Low**

Add IDs for export and localization workflows.

#### 3.1 Technical ID

Auto-generated slug based on speaker + first words, but editable.

**Auto-generation logic**:
```elixir
def generate_technical_id(speaker_name, text) do
  base = "#{speaker_name}_#{first_words(text, 3)}"
  base
  |> String.downcase()
  |> String.replace(~r/[^a-z0-9]+/, "_")
  |> String.trim("_")
end
```

**Properties Panel**: Text input with "Generate" button.

#### 3.2 External ID

Free-form text for localization tool integration (e.g., Crowdin, Lokalise).

**Properties Panel**: Text input with copy button.

#### 3.3 Word Count Display

Show word count for text fields (useful for VO budgeting).

**Properties Panel**: Small badge showing word count for each text field.

#### Tasks
- [ ] Add technical_id field with auto-generation
- [ ] Add external_id field
- [ ] Create ID generator helper function
- [ ] Add word count display component
- [ ] Add copy-to-clipboard for IDs

---

### Phase 4: Logic & Conditions
**Priority: Important | Effort: Medium**

Add input conditions and output instructions like articy:draft.

#### 4.1 Input Condition

Condition that must be true for this dialogue to be reachable/visible.

**Use cases**:
- `has_item("key")` - Only show if player has item
- `reputation > 50` - Only show if reputation is high
- `quest_started("main")` - Only show during quest

**Properties Panel**:
- Collapsible section "Conditions & Actions"
- Code input with syntax highlighting (monospace)
- Help tooltip explaining syntax

#### 4.2 Output Instruction

Action(s) to execute when leaving this node (regardless of response).

**Use cases**:
- `set("talked_to_merchant", true)`
- `add_item("map")`
- `reputation += 10`

**Properties Panel**:
- Code input in same collapsible section
- Multi-line support

#### 4.3 Enhanced Responses

Add `instruction` field to responses for response-specific actions.

**Use case**: Different responses trigger different variable changes.

#### Tasks
- [ ] Add input_condition field
- [ ] Add output_instruction field
- [ ] Add instruction field to responses
- [ ] Create collapsible "Logic" section in properties panel
- [ ] Add syntax highlighting for code inputs
- [ ] Add help documentation for expression syntax
- [ ] Update export format to include conditions/instructions

---

### Phase 5: Templates System
**Priority: Nice to Have | Effort: High**

Allow defining reusable dialogue templates with custom properties.

#### 5.1 Database Schema

```elixir
# New table: dialogue_templates
schema "dialogue_templates" do
  field :name, :string                    # "Quest Dialogue", "Shop Interaction"
  field :description, :string
  field :color, :string                   # Default color for this template
  field :properties_schema, :map          # JSON Schema for custom properties
  field :default_properties, :map         # Default values

  belongs_to :project, Project
  timestamps()
end

# Example properties_schema:
%{
  "quest_id" => %{"type" => "string", "label" => "Quest ID"},
  "is_repeatable" => %{"type" => "boolean", "label" => "Repeatable", "default" => false},
  "importance" => %{"type" => "select", "label" => "Importance", "options" => ["low", "medium", "high"]}
}
```

#### 5.2 Template Management UI

**Location**: Project Settings > Dialogue Templates

- List of templates
- Create/Edit template form
- Define custom properties with types:
  - String
  - Number
  - Boolean
  - Select (with options)
  - Asset reference
  - Page reference

#### 5.3 Template Selection in Dialogue Node

**Properties Panel**:
- Template selector at top (optional)
- When template selected, show custom property fields
- Template color applies automatically (can be overridden)

#### 5.4 Template Inheritance

- Changing a template updates all dialogues using it
- Custom properties are merged, not replaced

#### Tasks
- [ ] Create dialogue_templates migration
- [ ] Create DialogueTemplate schema
- [ ] Create Templates context functions
- [ ] Build template management UI in project settings
- [ ] Add template selector to dialogue properties panel
- [ ] Render dynamic custom property fields
- [ ] Handle template property updates across dialogues
- [ ] Export templates in project export

---

### Phase 6: Reference System
**Priority: Nice to Have | Effort: Medium**

Add a reference strip for related entities/assets (like articy:draft).

#### 6.1 Reference Strip

Allow attaching multiple references to a dialogue:
- Characters involved (besides speaker)
- Locations mentioned
- Items discussed
- Related documents/notes

**Data structure**:
```elixir
"references" => [
  %{"type" => "page", "id" => 123, "label" => "Location"},
  %{"type" => "asset", "id" => 456, "label" => "Item Image"}
]
```

#### 6.2 Properties Panel UI

- Collapsible "References" section
- Add reference button with type picker
- List of attached references with remove button
- Click reference to navigate to it

#### 6.3 Node Preview

- Show reference count badge on node
- Tooltip with reference names

#### Tasks
- [ ] Add references field to dialogue data
- [ ] Create reference picker component
- [ ] Add references section to properties panel
- [ ] Update node preview with reference indicator
- [ ] Add navigation to referenced items

---

### Phase 7: Enhanced Node Display
**Priority: Nice to Have | Effort: Medium**

Improve the visual representation of dialogue nodes on the canvas.

#### 7.1 Speaker Avatar on Node

Show speaker's avatar (from Page cover image) on the node.

**Node layout**:
```
┌─────────────────────────────┐
│ [Avatar] Speaker Name    🎨 │  <- Header with avatar + color indicator
├─────────────────────────────┤
│ (stage directions)          │  <- Italic, dimmed
│ "Dialogue preview text..."  │  <- Main text preview
├─────────────────────────────┤
│ 🔊 📎                       │  <- Audio + references indicators
├─────────────────────────────┤
│ ○ Response 1            ──○ │  <- Outputs
│ ○ Response 2            ──○ │
└─────────────────────────────┘
```

#### 7.2 Expanded/Collapsed Modes

- **Collapsed**: Just speaker + first line
- **Expanded**: Full preview with all fields

Toggle via double-click or button.

#### 7.3 Visual Indicators

- 🎨 Color dot/stripe
- 🔊 Audio attached
- 📎 References attached
- ⚡ Has conditions/instructions
- 📋 Uses template

#### Tasks
- [ ] Add speaker avatar to node header
- [ ] Implement expanded/collapsed toggle
- [ ] Add visual indicator icons
- [ ] Update node width calculation for content
- [ ] Add tooltip previews for truncated content

---

## UI Mockups

### Properties Panel Layout

```
┌─────────────────────────────────────┐
│ 💬 Dialogue                      ✕ │
├─────────────────────────────────────┤
│                                     │
│ Template      [None ▼]              │
│                                     │
│ ─────────── Speaker ─────────────   │
│                                     │
│ Character    [Select... ▼]          │
│              [Avatar preview]       │
│                                     │
│ ─────────── Content ──────────────  │
│                                     │
│ Stage        ┌───────────────────┐  │
│ Directions   │ (whispering)      │  │
│              └───────────────────┘  │
│                                     │
│ Full Text    ┌───────────────────┐  │
│              │ Rich text editor  │  │
│              │                   │  │
│              └───────────────────┘  │
│              12 words               │
│                                     │
│ Menu Text    ┌───────────────────┐  │
│              │ Short version...  │  │
│              └───────────────────┘  │
│                                     │
│ ─────────── Visual ───────────────  │
│                                     │
│ Color        [Purple ▼]             │
│                                     │
│ Cover Image  [Select asset...]      │
│              [Thumbnail preview]    │
│                                     │
│ Audio        [Select asset...]      │
│              [▶️ Preview]            │
│                                     │
│ ▼ Logic ──────────────────────────  │
│                                     │
│ Input        ┌───────────────────┐  │
│ Condition    │ reputation > 50   │  │
│              └───────────────────┘  │
│                                     │
│ Output       ┌───────────────────┐  │
│ Instruction  │ set("met", true)  │  │
│              └───────────────────┘  │
│                                     │
│ ▼ Technical ──────────────────────  │
│                                     │
│ Technical ID [merchant_hello] [⟳]   │
│ External ID  [dlg_001_merchant] [📋]│
│                                     │
│ ▼ References ─────────────────────  │
│                                     │
│ [+ Add reference]                   │
│ • 📄 Market Square (location)       │
│ • 🎭 Old Merchant (character)       │
│                                     │
│ ─────────── Responses ────────────  │
│                                     │
│ ┌───────────────────────────────┐   │
│ │ "Tell me about the sword"     │   │
│ │ Menu: "Ask about sword"       │   │
│ │ Condition: has_gold > 100     │   │
│ │ Action: set("asked_sword")    │   │
│ └───────────────────────────────┘   │
│                                     │
│ [+ Add response]                    │
│                                     │
├─────────────────────────────────────┤
│ [▶️ Preview from here]              │
│ [🗑️ Delete Node]                    │
└─────────────────────────────────────┘
```

### Node Canvas Display

```
┌─────────────────────────────────────┐
│ ● │ 🧙 Old Merchant          🔊 📎 │  <- Purple dot, avatar, name, indicators
├───┴─────────────────────────────────┤
│ (leaning forward, conspiratorially) │  <- Stage directions (italic, dim)
├─────────────────────────────────────┤
│ "I've got something special for     │  <- Text preview
│ you today, traveler..."             │
├─────────────────────────────────────┤
│ ⚡ reputation > 50                  │  <- Condition indicator
├─────────────────────────────────────┤
│ ○───────────────────────────────────│  <- Input
│                    "Show me"      ○─│  <- Output responses
│                    "Not interested" ○─│
│                    "Who are you?" ○─│
└─────────────────────────────────────┘
```

---

## Data Migration Strategy

Since `data` is JSONB, existing dialogues will continue to work. New fields will be `nil`/empty until edited.

**Migration helper** (optional, run once):
```elixir
def migrate_dialogue_data do
  from(n in FlowNode, where: n.type == "dialogue")
  |> Repo.all()
  |> Enum.each(fn node ->
    new_data = Map.merge(default_dialogue_data(), node.data)
    node
    |> FlowNode.data_changeset(%{data: new_data})
    |> Repo.update()
  end)
end
```

---

## Export Format Enhancement

Update JSON export to include all new fields:

```json
{
  "nodes": [
    {
      "id": "uuid",
      "type": "dialogue",
      "position": {"x": 100, "y": 200},
      "data": {
        "speaker": {
          "id": "page_123",
          "name": "Old Merchant",
          "avatar": "asset_url"
        },
        "text": {
          "full": "<p>I've got something special...</p>",
          "menu": "Merchant greeting",
          "stage_directions": "(leaning forward)"
        },
        "visual": {
          "color": "purple",
          "cover_image": "asset_url",
          "audio": "asset_url"
        },
        "technical": {
          "id": "merchant_greeting_01",
          "external_id": "dlg_merchant_001"
        },
        "logic": {
          "input_condition": "reputation > 50",
          "output_instruction": "set('met_merchant', true)"
        },
        "template": {
          "id": "quest_dialogue",
          "properties": {
            "quest_id": "main_quest",
            "importance": "high"
          }
        },
        "references": [
          {"type": "page", "id": "page_456", "name": "Market Square"}
        ],
        "responses": [
          {
            "id": "resp_1",
            "text": "Show me what you have",
            "menu_text": "Show me",
            "condition": "gold > 100",
            "instruction": "set('browsing', true)"
          }
        ]
      }
    }
  ]
}
```

---

## Implementation Order

| Phase                    | Priority     | Effort   | Dependencies           |
|--------------------------|--------------|----------|------------------------|
| 1. Core Text Fields      | Essential    | Low      | None                   |
| 2. Visual Customization  | Essential    | Medium   | Phase 1, Assets system |
| 3. Technical IDs         | Important    | Low      | Phase 1                |
| 4. Logic & Conditions    | Important    | Medium   | Phase 1                |
| 5. Templates             | Nice to Have | High     | Phase 1-4              |
| 6. Reference System      | Nice to Have | Medium   | Phase 1                |
| 7. Enhanced Node Display | Nice to Have | Medium   | Phase 1-2              |

**Recommended implementation sequence**:
1. Phase 1 (foundation)
2. Phase 3 (quick win)
3. Phase 2 (visual impact)
4. Phase 4 (logic capabilities)
5. Phase 7 (UX polish)
6. Phase 6 (references)
7. Phase 5 (templates - complex)

---

## Testing Checklist

### Phase 1
- [ ] New dialogue nodes have all default fields
- [ ] Existing dialogues continue to work
- [ ] Stage directions save and display
- [ ] Menu text saves and displays
- [ ] Rich text editor still works for main text

### Phase 2
- [ ] Color selector works
- [ ] Node renders with selected color
- [ ] Cover image picker works
- [ ] Cover image shows in node
- [ ] Audio picker works
- [ ] Audio preview plays

### Phase 3
- [ ] Technical ID auto-generates correctly
- [ ] Technical ID can be manually edited
- [ ] External ID saves correctly
- [ ] Copy buttons work
- [ ] Word count displays accurately

### Phase 4
- [ ] Input condition saves
- [ ] Output instruction saves
- [ ] Response instruction saves
- [ ] Conditions shown in node preview
- [ ] Export includes all logic fields

### Phase 5
- [ ] Templates can be created
- [ ] Templates can be assigned to dialogues
- [ ] Custom properties render correctly
- [ ] Template changes propagate to dialogues
- [ ] Export includes template data

### Phase 6
- [ ] References can be added
- [ ] References can be removed
- [ ] Click navigates to reference
- [ ] Reference count shows on node

### Phase 7
- [ ] Speaker avatar shows on node
- [ ] Expanded/collapsed toggle works
- [ ] All indicators display correctly
- [ ] Tooltips work

---

## References

- [articy:draft Dialogue Fragments](https://www.articy.com/help/adx/Flow_Objects_DialogFragment.html)
- [articy:draft Dialogues](https://www.articy.com/help/adx/Flow_Dialog.html)
- [articy:draft Tutorial L06](https://www.articy.com/en/articydraft-first-steps-tutorial-series-l06-creating-a-dialogue/)
- [Arcweave Elements](https://docs.arcweave.com/project-items/elements)
- [Arcweave Components](https://docs.arcweave.com/project-items/components)
- [Arcweave Hology Integration](https://docs.hology.app/integrations/arcweave)
