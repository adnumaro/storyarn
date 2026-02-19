# Plan: FigJam-style Floating Toolbar for Map Canvas

## Context

The map editor currently uses a fixed right sidebar (`w-72`) to show properties of the selected element. This eats 288px of canvas space and forces the user to shift attention away from the element. We want to replace it with a compact floating toolbar positioned directly above the selected element — the same pattern FigJam uses.

Additionally, the "Map Properties" sidebar (shown when nothing is selected) will become a floating panel triggered by a gear button in the header.

**Key design principles:**
- Dark-themed floating toolbar above the selected element
- Shared widget components reused across element types (color picker, border picker, etc.)
- Popovers open/close via `JS.toggle` (zero server round-trips)
- JS manages positioning; LiveView manages content
- Hide toolbar during drag, reposition on pan/zoom
- No toolbar for view-only users (only selection highlight)

---

## Architecture

```
User clicks element on canvas
  → JS pushes "select_element"
  → Server assigns selected_element/selected_type → LiveView re-renders toolbar content
  → Server pushes "element_selected" back to JS
  → JS computes screen coords from Leaflet element → positions toolbar div → shows it

User opens popover (color/border/etc.)
  → JS.toggle (client-only, no round-trip)

User picks a color
  → phx-click fires → server updates → re-renders toolbar (new swatch highlighted)

User pans/zooms map
  → JS repositions toolbar via Leaflet latLngToContainerPoint

User drags element
  → JS hides toolbar → drag ends → JS repositions and shows
```

**The toolbar div** lives inside the canvas area as a sibling to `#map-canvas`. LiveView patches its children (which toolbar is shown, current values). JS only writes `style.left`, `style.top`, and visibility classes on it — these don't conflict with LiveView's morphdom patching.

---

## Files Overview

| Action | File | What changes |
|--------|------|-------------|
| CREATE | `lib/storyarn_web/live/map_live/components/toolbar_widgets.ex` | Shared widgets: color_picker, border_picker, size_picker, layer_picker, target_picker, opacity_slider |
| CREATE | `lib/storyarn_web/live/map_live/components/floating_toolbar.ex` | Per-type toolbars: zone, pin, connection, annotation |
| CREATE | `assets/js/map_canvas/floating_toolbar.js` | JS positioning module |
| MODIFY | `lib/storyarn_web/live/map_live/show.ex` | Remove both sidebars, add floating toolbar div + map settings panel, add settings button to header |
| MODIFY | `assets/js/hooks/map_canvas.js` | Import + wire floating toolbar, add map move/zoom handlers |
| MODIFY | `assets/js/map_canvas/handlers/connection_handler.js` | Expose `lines` Map in return object |
| MODIFY | `assets/js/map_canvas/handlers/annotation_handler.js` | Add dblclick → inline text editing, expose `enableInlineEditing` |
| MODIFY | `assets/js/map_canvas/annotation_renderer.js` | Add `data-annotation-text` attr to text div for DOM access |
| MODIFY | `assets/css/app.css` | Add floating toolbar + widget styles |
| DELETE (code only) | `lib/storyarn_web/live/map_live/components/properties_panel.ex` | Replaced by floating_toolbar.ex |
| DELETE (code only) | `lib/storyarn_web/live/map_live/components/element_panels.ex` | Replaced by floating_toolbar.ex |
| MODIFY | `lib/storyarn_web/live/map_live/components/map_header.ex` | Add settings gear button |
| MODIFY | `priv/gettext/*/LC_MESSAGES/maps.po` | New strings |

---

## Phase 1 — Shared Toolbar Widget Components

### File: `lib/storyarn_web/live/map_live/components/toolbar_widgets.ex`

Module `StoryarnWeb.MapLive.Components.ToolbarWidgets` with `use Phoenix.Component`.

### 1.1 Color Swatch Picker (`toolbar_color_picker/1`)

A button showing the current color as a filled circle. Clicking opens a popover with:
- 24 preset color swatches in a 6×4 grid (2 rows of 12)
- A "custom" button that triggers a hidden `<input type="color">`

```elixir
attr :id, :string, required: true          # unique suffix, e.g. "zone-fill-123"
attr :event, :string, required: true       # "update_zone"
attr :element_id, :any, required: true     # zone.id
attr :field, :string, required: true       # "fill_color"
attr :value, :string, required: true       # current hex "#3b82f6"
attr :label, :string, required: true       # tooltip "Fill Color"
attr :disabled, :boolean, default: false
slot :extra_content                        # for opacity slider inside the popover
```

**Preset palette** (module attribute `@color_swatches`):
```
Row 1: #ef4444 #f97316 #f59e0b #eab308 #22c55e #14b8a6 #3b82f6 #6366f1 #8b5cf6 #a855f7 #ec4899 #000000
Row 2: #fca5a5 #fdba74 #fde68a #d9f99d #a7f3d0 #a5f3fc #93c5fd #c4b5fd #e9d5ff #fbcfe8 #e5e7eb #ffffff
```

**Swatch click** → `phx-click={JS.push(@event, value: %{id: @element_id, field: @field, value: color})}`.

**Custom color** → `<input type="color">` wrapped in a `<form phx-change={@event}>` with hidden inputs for element_id + field. Triggered via `<label for={native_id}>`.

**Popover** → `JS.toggle(to: "#popover-#{@id}")`. The `:extra_content` slot renders after the swatch grid (used for opacity slider in zones).

### 1.2 Border Picker (`toolbar_border_picker/1`)

Button showing current border style as a small line icon. Popover contains:
- **Style tabs**: Solid | Dashed | Dotted — as icon buttons with line-style SVG previews
- **Color swatches**: same 24-color grid, for border color
- **Width stepper**: `−` `[value]` `+` compact stepper (values 0-10)

```elixir
attr :id, :string, required: true
attr :event, :string, required: true
attr :element_id, :any, required: true
attr :current_style, :string, default: "solid"
attr :current_color, :string, default: "#1e40af"
attr :current_width, :integer, default: 2
attr :disabled, :boolean, default: false
```

### 1.3 Opacity Slider (`toolbar_opacity_slider/1`)

Rendered inside the fill color popover (via `:extra_content` slot). Compact range slider with percentage label.

```elixir
attr :event, :string, required: true
attr :element_id, :any, required: true
attr :value, :float, default: 0.3
attr :disabled, :boolean, default: false
```

Uses `<form phx-change={@event}>` with hidden inputs + `<input type="range">`.

### 1.4 Layer Picker (`toolbar_layer_picker/1`)

Button with layers icon. Popover shows layer list as radio-style options.

```elixir
attr :id, :string, required: true
attr :event, :string, required: true
attr :element_id, :any, required: true
attr :current_layer_id, :any, default: nil
attr :layers, :list, default: []
attr :disabled, :boolean, default: false
```

### 1.5 Target Picker (`toolbar_target_picker/1`)

Button showing current target (icon + truncated name, or "No link"). Popover with two steps:
- **Step 1**: Type buttons — Sheet / Flow / Map / URL
- **Step 2**: Resource list (scrollable, max-h-48) or URL input

Step transitions via `JS.hide` + `JS.show` — no round-trip.

```elixir
attr :id, :string, required: true
attr :event, :string, required: true
attr :element_id, :any, required: true
attr :current_type, :string, default: nil
attr :current_target_id, :any, default: nil
attr :target_types, :list, default: ~w(sheet flow map)
attr :project_maps, :list, default: []
attr :project_sheets, :list, default: []
attr :project_flows, :list, default: []
attr :disabled, :boolean, default: false
```

### 1.6 Size Picker (`toolbar_size_picker/1`)

Inline pill buttons (S / M / L) as a button group. No popover needed.

```elixir
attr :event, :string, required: true
attr :element_id, :any, required: true
attr :field, :string, default: "size"
attr :current, :string, default: "md"
attr :options, :list, default: [{"sm", "S"}, {"md", "M"}, {"lg", "L"}]
attr :disabled, :boolean, default: false
```

---

## Phase 2 — Per-Type Floating Toolbars

### File: `lib/storyarn_web/live/map_live/components/floating_toolbar.ex`

Module `StoryarnWeb.MapLive.Components.FloatingToolbar` importing toolbar_widgets.

### 2.1 Main dispatcher (`floating_toolbar/1`)

Dispatches to per-type component via `:if` guards on `@selected_type`.

### 2.2 Zone Toolbar

```
[Name input] | [Fill color▾ (+opacity)] [Border▾] | [Layer▾] [Lock] | [… more]
```

- **Name**: `toolbar-input` `w-24`, `phx-blur="update_zone"`
- **Fill color**: `toolbar_color_picker` with opacity slider in `:extra_content` slot
- **Border**: `toolbar_border_picker` (style + color + width in one popover)
- **Layer**: `toolbar_layer_picker`
- **Lock**: icon toggle, `phx-click={JS.push("update_zone", value: ...)}`
- **More (…)**: popover with tooltip input + `toolbar_target_picker`

### 2.3 Pin Toolbar

```
[Label input] | [Type▾] [Color▾] [Size S|M|L] | [Layer▾] [Lock] | [… more]
```

- **Type**: popover with 4 options (Location/Character/Event/Custom)
- **More (…)**: tooltip + target picker + "Change Icon" button (opens existing icon upload modal)

### 2.4 Connection Toolbar

```
[Label input] | [Style ···] [Color▾] | [Show Label] [Bidirectional] | [… more]
```

- **Style**: 3 inline icon buttons (solid/dashed/dotted), no popover
- **More (…)**: "Straighten path" button (if waypoints > 0)

### 2.5 Annotation Toolbar

```
[Color▾] [Size S|M|L] | [Layer▾] [Lock]
```

Compact — no "more" button needed. Text editing is done inline on the canvas (see Phase 3.5).

---

## Phase 3 — Template + JS Integration

### 3.1 Template changes (`show.ex`)

**Remove**: Both `<aside>` blocks (lines 117-196). Remove imports for `PropertiesPanel`, `ElementPanels`.

**Add imports**: `FloatingToolbar`, `ToolbarWidgets`.

**Add** inside `div.flex-1.relative.overflow-hidden` (after legend):

```heex
<%!-- Floating element toolbar --%>
<div :if={@selected_element && @can_edit && @edit_mode}
     id="floating-toolbar-content"
     class="absolute z-[1050]"
     style="display: none;">
  <.floating_toolbar
    selected_type={@selected_type}
    selected_element={@selected_element}
    layers={@layers}
    can_edit={not Map.get(@selected_element || %{}, :locked, false)}
    can_toggle_lock={true}
    project_maps={@project_maps}
    project_sheets={@project_sheets}
    project_flows={@project_flows}
  />
</div>

<%!-- Map settings floating panel --%>
<div id="map-settings-floating"
     class="hidden absolute top-3 right-3 z-[1000] w-72 max-h-[calc(100vh-8rem)]
            overflow-y-auto bg-base-100 rounded-xl border border-base-300 shadow-xl">
  <!-- header with close button, map_properties content -->
</div>
```

**Add gear button** in `map_header.ex` (next to Edit/View toggle).

### 3.2 JS Positioning Module (`assets/js/map_canvas/floating_toolbar.js`)

Factory function `createFloatingToolbar(hook)` returning `{ show, hide, reposition, setDragging }`.

Core logic:
- `show(type, id)` — stores current selection, calls `position()` inside `requestAnimationFrame`
- `position()` — reads element's Leaflet coordinates → `latLngToContainerPoint` → sets `style.left/top/display` on `#floating-toolbar-content`
- `hide()` — sets `display: none`
- `reposition()` — re-calls `position()` for current selection (called on map move/zoom)
- `setDragging(bool)` — hides during drag, repositions on drag end

**Element coordinate extraction:**
- Pin: `markers.get(id).getLatLng()` → container point, offset -20px above pin icon
- Zone: `getPolygon(id).getBounds()` → center of north edge
- Annotation: `markers.get(id).getLatLng()` → container point, offset -30px above
- Connection: `lines.get(id).getLatLngs()` → midpoint

**Edge clamping**: Clamp left to `[MARGIN, canvasWidth - toolbarWidth - MARGIN]`. If top < MARGIN, flip toolbar below the element.

### 3.3 Wiring into `map_canvas.js`

```javascript
import { createFloatingToolbar } from "../map_canvas/floating_toolbar.js";

// In initCanvas(), after handlers:
this.floatingToolbar = createFloatingToolbar(this);

// In element_selected handler:
this.floatingToolbar.show(type, id);
// Also close map settings panel

// In element_deselected handler:
this.floatingToolbar.hide();

// Map events:
this.leafletMap.on("move", () => this.floatingToolbar?.reposition());
this.leafletMap.on("zoom", () => this.floatingToolbar?.reposition());
```

**Drag hide/show** — add to each handler:
- `pin_handler.js`: `marker.on("dragstart/dragend")`
- `zone_handler.js`: polygon `mousedown` / `onDragEnd`
- `annotation_handler.js`: `marker.on("dragstart/dragend")`

### 3.4 Connection handler fix

**File: `assets/js/map_canvas/handlers/connection_handler.js`**

Add `lines` to the return object (currently private, not exposed):
```javascript
return {
  // ... existing ...
  lines,  // ← ADD
};
```

### 3.5 Annotation inline text editing (NEW FEATURE)

Currently annotations render as post-it divIcons with escaped text (`annotation_renderer.js:buildAnnotationHtml`). There's no inline editing — the sidebar textarea was the only way to edit text.

**Changes needed:**

**`annotation_handler.js`** — Add dblclick handler on annotation markers:
```javascript
marker.on("dblclick", (e) => {
  L.DomEvent.stopPropagation(e);
  if (!hook.editMode || annotation.locked) return;
  enableInlineEditing(marker);
});
```

**`annotation_handler.js`** — New `enableInlineEditing(marker)` function:
1. Find the text div inside the marker's DOM element (`marker.getElement()`)
2. Set `contentEditable = "true"` on it
3. Focus and select all text
4. Disable marker dragging temporarily
5. On `blur` or `Enter`: read `textContent`, push `update_annotation` event, restore non-editable state, re-enable dragging

**`annotation_renderer.js`** — Add an id or data attribute to the text div so it can be found by the handler (e.g., `data-annotation-text`).

**`map_canvas.js`** — Update `focus_annotation_text` handler to use the new inline editing:
```javascript
this.handleEvent("focus_annotation_text", ({ id }) => {
  requestAnimationFrame(() => {
    const annId = id || this.annotationHandler?.selectedId;
    if (annId) this.annotationHandler.enableInlineEditing(markers.get(annId));
  });
});
```

**`annotation_handler.js`** — Expose `enableInlineEditing` in return object.

---

## Phase 4 — CSS

### File: `assets/css/app.css`

New classes:
- `.floating-toolbar` — dark background, rounded, flex layout, shadow
- `.toolbar-btn` — 28px height, dark text on dark bg, hover highlight
- `.toolbar-btn-active` — brighter background
- `.toolbar-separator` — 1px vertical divider
- `.toolbar-input` — dark input field (name/label text inputs)
- `.toolbar-popover` — light theme popover (uses `--color-base-*` vars)
- `.color-swatch` — 22px circle, hover scale, selected ring
- `#floating-toolbar-content` — opacity/transform transition for animate in/out

---

## Phase 5 — Polish & Cleanup

### 5.1 Popover dismiss on click-away
Document click listener that hides any open popovers not containing the click target.

### 5.2 Toolbar animations
Opacity + translateY transition (0.12s) using `.toolbar-visible` class instead of display toggle.

### 5.3 Map settings panel animation
`JS.show`/`JS.hide` with transition: `opacity-0 scale-95` → `opacity-100 scale-100`.

### 5.4 Gettext strings
Add: "Map Settings", "Fill", "Border", "Opacity", "More", "No link", "Back", etc.

### 5.5 Delete old files
Remove `properties_panel.ex`, `element_panels.ex`, and their imports from `show.ex`.

---

## Verification

```bash
mix compile --warnings-as-errors
```

Manual tests:
1. Select zone → toolbar above with correct values → pick fill color → updates
2. Open border popover → change style/color/width → zone updates
3. Type name → blur → zone name updates
4. Drag zone → toolbar hides → release → reappears at new position
5. Pan/zoom → toolbar follows element
6. Select pin → pin toolbar with type/color/size/layer/lock
7. Select connection → connection toolbar with style/color/toggles
8. Select annotation → annotation toolbar with color/size/layer/lock
9. Click empty canvas → toolbar disappears
10. Gear icon → map settings panel floats open → X closes it
11. View-only user → no toolbar shown
12. Escape → deselect → toolbar hides
13. Open popover → click outside → popover closes
14. Element near top edge → toolbar flips below element
