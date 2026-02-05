# Dialogue Node Enhancement Plan

> **Objective**: Enhance Storyarn's dialogue node to match the feature set of articy:draft and Arcweave, the industry-leading narrative design tools.

> **Related Documents**:
> - [Research: Condition Placement](./docs/research/DIALOGUE_CONDITIONS_RESEARCH.md)
> - [Recommendations: Condition Model](./docs/DIALOGUE_CONDITIONS_RECOMMENDATIONS.md)

---

## Implementation Status

| Phase | Name | Priority | Status |
|-------|------|----------|--------|
| 1 | Core Dialogue Enhancement | Essential | ✅ COMPLETED |
| 2 | Visual Customization | Essential | ✅ COMPLETED (audio only, color/cover deferred) |
| 3 | Technical Identifiers | Important | ✅ COMPLETED |
| 4 | Logic & Conditions | Important | ✅ COMPLETED |
| 5 | Templates System | Nice to Have | ⏳ PENDING |
| 6 | Reference System | Nice to Have | ⏳ PENDING |
| 7 | Enhanced Node Display | Nice to Have | ⏳ PENDING |

---

## Current Implementation

The dialogue node now has a professional-grade feature set:

```elixir
# lib/storyarn_web/live/flow_live/components/node_type_helpers.ex
def default_node_data("dialogue") do
  %{
    # === SPEAKER ===
    "speaker_page_id" => nil,

    # === TEXT FIELDS ===
    "text" => "",
    "stage_directions" => "",
    "menu_text" => "",

    # === VISUAL ===
    "audio_asset_id" => nil,

    # === TECHNICAL ===
    "technical_id" => "",
    "localization_id" => generate_localization_id(),

    # === LOGIC ===
    "input_condition" => "",
    "output_instruction" => "",

    # === RESPONSES ===
    "responses" => []
  }
end

# Response structure
%{
  "id" => "uuid",
  "text" => "",
  "condition" => "",      # Visibility condition (uses condition builder)
  "instruction" => ""     # Action when selected
}

# Condition node (multi-output)
def default_node_data("condition") do
  %{
    "expression" => "",
    "cases" => [
      %{"id" => "case_true", "value" => "true", "label" => "True"},
      %{"id" => "case_false", "value" => "false", "label" => "False"}
    ]
  }
end
```

### Key Files

| Component | File |
|-----------|------|
| Node defaults | `lib/storyarn_web/live/flow_live/components/node_type_helpers.ex` |
| Properties panel | `lib/storyarn_web/live/flow_live/components/properties_panels.ex` |
| Screenplay editor | `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` |
| Canvas rendering | `assets/js/hooks/flow_canvas/components/storyarn_node.js` |
| Node config | `assets/js/hooks/flow_canvas/node_config.js` |
| Condition builder | `lib/storyarn_web/components/condition_builder.ex` |
| Flow show | `lib/storyarn_web/live/flow_live/show.ex` |

---

## Completed Phases Summary

### Phase 1: Core Dialogue Enhancement ✅

**Dynamic Node Header:**
- Speaker avatar and name shown when speaker selected
- Falls back to default dialogue icon/label
- Keeps blue dialogue color (#3b82f6)

**Text Fields:**
- `stage_directions` - Plain text, shown on canvas (italic, dimmed)
- `menu_text` - Collapsible section in sidebar

**Dual Editing Modes:**
- **Sidebar** (single click) - Full properties panel
- **Screenplay** (double click) - Fullscreen writing mode
- Mutual exclusivity enforced
- Esc to close screenplay

### Phase 2: Visual Customization ✅

**Audio Asset:**
- `audio_asset_id` field
- Dropdown selector filtered by audio content type
- HTML5 audio preview player
- 🔊 indicator on canvas when audio attached

**Deferred:**
- Node colors → Will use speaker Page color (FUTURE_FEATURES.md)
- Cover image → Nice to have (FUTURE_FEATURES.md)

### Phase 3: Technical Identifiers ✅

**Technical ID:**
- Format: `{flow_slug}_{speaker}_{count}`
- Auto-generated via "Generate" button
- Manually editable

**Localization ID:**
- Format: `dialogue.{context}.{uuid_suffix}`
- Auto-generated on node creation
- Copy button included

**Word Count:**
- Badge display showing word count
- Strips HTML before counting

### Phase 4: Logic & Conditions ✅

**Connection Conditions - REMOVED:**
- Based on [research](./docs/research/DIALOGUE_CONDITIONS_RESEARCH.md)
- No major tool uses edge-based conditions
- All routing via Condition nodes

**Multi-Output Condition Node:**
- `cases` array with id, value, label
- Dynamic outputs rendered on canvas
- Add/remove cases in properties panel
- Default case (empty value) supported
- Database migration completed

**Dialogue Logic Fields:**
- `input_condition` - Visibility guard (🔒 indicator)
- `output_instruction` - Side effect on exit (⚡ indicator)
- Collapsible "Logic" section in properties

**Response Logic:**
- `condition` - Uses visual condition builder
- `instruction` - Plain text action
- [?] badge on responses with conditions

---

## Pending Phases

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

- List of templates with create/edit/delete
- Property types: String, Number, Boolean, Select, Asset reference, Page reference
- Color picker for template default color

#### 5.3 Template Selection in Dialogue Node

- Template selector dropdown at top of properties panel
- Custom property fields rendered dynamically
- Template color auto-applies (can override)

#### 5.4 Template Inheritance

- Changing template schema updates all dialogues using it
- Custom property values are preserved when possible

#### Tasks
- [ ] Create `dialogue_templates` migration
- [ ] Create `DialogueTemplate` schema in Flows context
- [ ] Create Templates CRUD functions
- [ ] Build template management UI in project settings
- [ ] Add template selector to dialogue properties panel
- [ ] Render dynamic custom property fields based on schema
- [ ] Handle template property updates across dialogues
- [ ] Include templates in project export

#### Data Structure Update
```elixir
# Add to dialogue node data
%{
  # ... existing fields ...
  "template_id" => nil,           # Reference to DialogueTemplate
  "template_properties" => %{}    # Custom properties from template
}
```

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

#### 6.2 Data Structure

```elixir
# Add to dialogue node data
%{
  # ... existing fields ...
  "references" => [
    %{"type" => "page", "id" => "page_123", "label" => "Location"},
    %{"type" => "asset", "id" => "asset_456", "label" => "Item Image"}
  ]
}
```

#### 6.3 Properties Panel UI

- Collapsible "References" section
- Add reference button with type picker (Page/Asset)
- List of attached references with remove button
- Click reference to navigate to it

#### 6.4 Node Preview

- 📎 indicator when references attached
- Tooltip with reference names

#### Tasks
- [ ] Add `references` field to dialogue default data
- [ ] Create reference picker component (reuse Page/Asset selectors)
- [ ] Add references section to properties panel
- [ ] Update node canvas with reference indicator (📎)
- [ ] Add navigation to referenced items on click
- [ ] Include references in export

---

### Phase 7: Enhanced Node Display
**Priority: Nice to Have | Effort: Medium**

Improve visual representation of dialogue nodes on canvas.

#### 7.1 Current Display

```
┌─────────────────────────────────┐
│ [Avatar] Old Merchant  🔒 ⚡ 🔊 │  ← Speaker + indicators
├─────────────────────────────────┤
│ (whispering)                    │  ← Stage directions (italic)
│ "I've got something..."         │  ← Text preview
├─────────────────────────────────┤
│ ○─────────────────────────────  │  ← Input
│              "Show me" [?] ──○  │  ← Response outputs
│         "Not interested"  ──○   │
└─────────────────────────────────┘
```

#### 7.2 Proposed Enhancements

**Expanded/Collapsed Modes:**
- **Collapsed**: Speaker + first line only (compact view)
- **Expanded**: Full preview with all fields (current default)
- Toggle via context menu or double-click on header

**Visual Indicators Summary:**
| Indicator | Meaning | Location |
|-----------|---------|----------|
| 🔒 | Has input_condition | Header right |
| ⚡ | Has output_instruction | Header right |
| 🔊 | Has audio attached | Header right |
| [?] | Response has condition | Response label |
| 📎 | Has references (Phase 6) | Header right |
| 📋 | Uses template (Phase 5) | Header right |

**Node Width:**
- Auto-calculate based on content length
- Minimum width for readability
- Maximum width to prevent sprawl

**Tooltips:**
- Full text on truncated content hover
- Condition expression on indicator hover

#### Tasks
- [ ] Implement expanded/collapsed node toggle
- [ ] Add collapse toggle to node context menu
- [ ] Persist collapse state per node (optional)
- [ ] Update node width calculation for content
- [ ] Add tooltip component for truncated content
- [ ] Add tooltip for indicators showing full expression

---

## Export Format

The JSON export should include all dialogue fields:

```json
{
  "nodes": [
    {
      "id": "uuid",
      "type": "dialogue",
      "position": {"x": 100, "y": 200},
      "data": {
        "speaker_page_id": "page_123",
        "text": "<p>I've got something special...</p>",
        "stage_directions": "(leaning forward)",
        "menu_text": "Merchant greeting",
        "audio_asset_id": "asset_789",
        "technical_id": "main_merchant_1",
        "localization_id": "dialogue.main.abc123",
        "input_condition": "reputation > 50",
        "output_instruction": "set('met_merchant', true)",
        "template_id": null,
        "template_properties": {},
        "references": [],
        "responses": [
          {
            "id": "resp_1",
            "text": "Show me what you have",
            "condition": "{\"logic\":\"and\",\"rules\":[...]}",
            "instruction": "set('browsing', true)"
          }
        ]
      }
    }
  ]
}
```

**Note:** Response conditions use the structured condition builder format (JSON), not plain expressions.

---

## Testing Checklist

### Phases 1-4 ✅ All Verified

**Core Features:**
- [x] New dialogue nodes have all default fields
- [x] Existing dialogues continue to work (backward compatible)
- [x] Stage directions save, load, and display on canvas
- [x] Menu text saves and loads in collapsible section
- [x] Speaker avatar and name shown in node header
- [x] Single click opens sidebar
- [x] Double click opens screenplay editor
- [x] Screenplay editor updates sync with sidebar
- [x] Esc closes screenplay

**Audio:**
- [x] Audio dropdown shows audio assets only
- [x] Audio preview player works
- [x] 🔊 indicator shows on canvas

**Technical:**
- [x] Technical ID auto-generates correctly
- [x] Technical ID can be manually edited
- [x] Localization ID auto-generated on creation
- [x] Copy button works
- [x] Word count displays accurately

**Logic:**
- [x] Input condition saves and loads
- [x] Output instruction saves and loads
- [x] Response condition builder works
- [x] Response instruction saves and loads
- [x] 🔒 indicator shows when input_condition set
- [x] ⚡ indicator shows when output_instruction set
- [x] [?] badge shows on responses with conditions

**Condition Node:**
- [x] New condition nodes have `cases` array
- [x] Existing nodes migrated (true/false default)
- [x] Cases can be added/removed
- [x] Dynamic outputs render on canvas
- [x] Connections to case outputs work
- [x] Default case (empty value) works

### Phase 5 (Templates) - Pending
- [ ] Templates can be created in project settings
- [ ] Templates can be edited/deleted
- [ ] Template selector shows in dialogue properties
- [ ] Custom properties render correctly
- [ ] Template changes propagate to dialogues
- [ ] Export includes template data

### Phase 6 (References) - Pending
- [ ] References field exists in dialogue data
- [ ] References can be added (pages and assets)
- [ ] References can be removed
- [ ] Click navigates to reference
- [ ] 📎 indicator shows on node canvas
- [ ] Export includes references

### Phase 7 (Enhanced Display) - Pending
- [ ] Expanded/collapsed toggle works
- [ ] Collapse state persists (if implemented)
- [ ] Node width adjusts to content
- [ ] Tooltips work on truncated content
- [ ] Indicator tooltips show expressions

---

## References

**Internal Documentation:**
- [Research: Condition Placement in Dialogue Systems](./docs/research/DIALOGUE_CONDITIONS_RESEARCH.md)
- [Recommendations: Dialogue Conditions Model](./docs/DIALOGUE_CONDITIONS_RECOMMENDATIONS.md)

**External References:**
- [articy:draft Dialogue Fragments](https://www.articy.com/help/adx/Flow_Objects_DialogFragment.html)
- [articy:draft Dialogues](https://www.articy.com/help/adx/Flow_Dialog.html)
- [articy:draft Conditions & Instructions](https://www.articy.com/help/adx/Scripting_Conditions_Instructions.html)
- [Arcweave Branches](https://arcweave.com/docs/1.0/branches)
- [Arcweave Elements](https://docs.arcweave.com/project-items/elements)
- [Arcweave Components](https://docs.arcweave.com/project-items/components)
