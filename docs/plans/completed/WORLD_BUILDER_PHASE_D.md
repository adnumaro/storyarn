# World Builder — Phase D: Pending & Integration

> **Goal:** Complete the remaining World Builder items: zone → child map drill-down creation,
> path labels, sheet backlinks, and sidebar tree elements.
>
> **Depends on:** Phases 1–3 + A + B + C complete (1908 tests passing, credo --strict green).
>
> **Baseline:** 1908 tests passing, 0 credo issues (February 2026).

---

## Summary

| # | Task | Priority | Effort |
|---|------|----------|--------|
| D1 | Zone label on canvas (centroid name) | 🔴 Critical | Small |
| D2 | Zone → create child map (full flow) | 🔴 Critical | Large |
| D3 | Path labels following connection curvature | 🟠 High | Medium |
| D4 | "Appears on Maps" in sheet References tab | 🟡 Medium | Small |
| D5 | Pins/zones as children in sidebar tree | 🟡 Medium | Medium |

**Recommended order:** D1 → D2 (D1 is prerequisite) → D3 → D4 → D5

---

## Task D1: Zone Label on Canvas (centroid name)

### Problem

Zone names exist in the DB (`zone.name`) but are never rendered inside the polygon on the
canvas. The user sees a colored shape but has no visual cue about what it represents unless
they hover (tooltip) or click (properties panel). The zone name should appear centered inside
the polygon at all times.

This is a prerequisite for D2: the user must see the zone name to know which zone to
right-click for child map creation.

### What already exists

- `zone_renderer.js` — creates `L.polygon` but no label (exports: `createZonePolygon`,
  `updateZonePolygon`, `updateZoneVertices`, `setZoneSelected`)
- `zone_handler.js` — manages polygon lifecycle (add/update/delete via server events),
  stores polygons in `const polygons = new Map()` (zone ID → L.Polygon)
- `zone.name` is already serialized in `map_data`
- Zone vertex centroid is not computed anywhere yet

### Implementation

#### `assets/js/map_canvas/zone_renderer.js`

Add two exported functions and one private helper:

```js
/**
 * Creates a non-interactive label marker at the polygon centroid.
 * Returns null when zone has no name.
 *
 * Uses textContent (not innerHTML) to avoid XSS concerns with zone names.
 */
export function createZoneLabelMarker(zone, w, h) {
  if (!zone.name) return null;

  const center = computeCentroid(zone.vertices, w, h);
  const span = document.createElement("span");
  span.textContent = zone.name;

  return L.marker(center, {
    icon: L.divIcon({
      className: "map-zone-label",
      html: span.outerHTML,
      iconSize: null,
      iconAnchor: null,
    }),
    interactive: false,
    keyboard: false,
    zIndexOffset: -100,  // below pins
  });
}

/**
 * Updates the label marker text and position.
 * If zone no longer has a name, returns false (caller should remove it).
 */
export function updateZoneLabelMarker(marker, zone, w, h) {
  if (!zone.name) return false;

  const span = marker.getElement()?.querySelector("span");
  if (span) span.textContent = zone.name;

  const center = computeCentroid(zone.vertices, w, h);
  marker.setLatLng(center);
  return true;
}

/**
 * Computes the visual centroid as the average of all vertex LatLngs.
 */
function computeCentroid(vertices, w, h) {
  if (!vertices || vertices.length === 0) return L.latLng(0, 0);
  const sum = vertices.reduce(
    (acc, v) => {
      const ll = toLatLng(v.x, v.y, w, h);
      return { lat: acc.lat + ll.lat, lng: acc.lng + ll.lng };
    },
    { lat: 0, lng: 0 }
  );
  return L.latLng(sum.lat / vertices.length, sum.lng / vertices.length);
}
```

#### `assets/js/map_canvas/handlers/zone_handler.js`

Add a second `Map` alongside `polygons` for label markers:

```js
const labelMarkers = new Map();  // zone ID → L.Marker (label)
```

Integration points (line references from current code):

1. **`addZoneToMap` (line 94):** After `polygon.addTo(hook.zoneLayer)` (line 229):
   ```js
   const label = createZoneLabelMarker(zone, hook.canvasWidth, hook.canvasHeight);
   if (label) {
     label.addTo(hook.zoneLayer);
     labelMarkers.set(zone.id, label);
   }
   ```

2. **`zone_updated` event (line 497):** After `updateZonePolygon(polygon, zone)` (line 501):
   ```js
   const existingLabel = labelMarkers.get(zone.id);
   if (existingLabel) {
     if (!updateZoneLabelMarker(existingLabel, zone, hook.canvasWidth, hook.canvasHeight)) {
       existingLabel.remove();
       labelMarkers.delete(zone.id);
     }
   } else if (zone.name) {
     const label = createZoneLabelMarker(zone, hook.canvasWidth, hook.canvasHeight);
     if (label) {
       label.addTo(hook.zoneLayer);
       labelMarkers.set(zone.id, label);
     }
   }
   ```

3. **`zone_vertices_updated` event (line 513):** After `updateZoneVertices(...)` (line 517):
   ```js
   const label = labelMarkers.get(zone.id);
   if (label) updateZoneLabelMarker(label, zone, hook.canvasWidth, hook.canvasHeight);
   ```

4. **`zone_deleted` event (line 522):** After `polygon.remove()` (line 525):
   ```js
   const label = labelMarkers.get(id);
   if (label) { label.remove(); labelMarkers.delete(id); }
   ```

5. **`destroy` (line 64):** Add `labelMarkers.clear();` alongside `polygons.clear()`.

#### `assets/css/app.css`

```css
.map-zone-label {
  pointer-events: none;
  user-select: none;
}
.map-zone-label span {
  display: block;
  white-space: nowrap;
  font-size: 0.75rem;
  font-weight: 600;
  color: white;
  text-shadow: 0 1px 3px rgba(0,0,0,0.8), 0 0 6px rgba(0,0,0,0.5);
  transform: translateX(-50%);  /* center horizontally */
}
```

### Tests

No server tests needed (pure JS). Manual verification:
- Zone with name → name appears centered inside polygon
- Zone name update via properties panel → label updates in real-time
- Zone vertex drag → label repositions to new centroid
- Zone with empty name → no label rendered
- Zone name cleared → label removed
- Zone name set on previously unnamed zone → label appears

### Verification

```bash
mix credo --strict
```

---

## Task D2: Zone → Create Child Map

### Overview

The user right-clicks on a named zone and selects "Create child map from zone".
This triggers a server-side pipeline that:
1. Extracts the bounding-box region of the parent map's background image
2. Upscales it 2× with Lanczos resampling (user can replace it later)
3. Uploads the resulting image via `Storage.upload/3` and creates an `Asset` record
4. Creates a child map with `parent_id = current_map.id`, the extracted image as background,
   the zone's name, and the inherited scale
5. Links the zone to the new child map (`target_type: "map"`, `target_id: new_map.id`)
6. Redirects the user to the child map

The user arrives on the child map and immediately sees the upscaled extract as background,
ready to continue working (adding pins, zones, sub-maps).

### What already exists (do NOT touch)

- `Maps.create_map/2` with `parent_id` — works
- `Maps.update_zone/2` — works
- `Maps.get_zone/2` — works
- `Assets.create_asset/2` — creates DB record (needs `filename`, `content_type`, `size`, `key`, `url`)
- `Assets.generate_key/2` — generates unique storage key like `"projects/1/assets/uuid/file.webp"`
- `Storage.upload/3` — uploads binary data to R2/S3 (or local), returns `{:ok, url}`
- `ImageProcessor` — has `get_dimensions/1`, `generate_thumbnail/2` (uses `Image` library)
- `{:image, "~> 0.62"}` — already a dependency (libvips wrapper, supports crop + resize)
- `zone_handler.js` lines 176–214 — zone context menu built inline (NOT in `context_menu_builder.js`)
- `tree_handlers.ex` `handle_create_child_map/2` — creates child from sidebar (keep as-is)
- `map_header.ex` — needs breadcrumb added (see below)
- `map.scale_value`, `map.scale_unit`, `map.width`, `map.height` — all stored on the map

### Part 2a: Right-click context menu item

#### `assets/js/map_canvas/handlers/zone_handler.js` (lines 186–213)

Add the new item **before** the delete separator (around line 206), inside the
`polygon.on("contextmenu", ...)` handler. The context menu items are built inline here,
NOT in `context_menu_builder.js` (which only exports shared utility functions).

```js
// After the duplicate item (~line 199) and before the separator (~line 202):
if (!data.locked) {
  items.push({
    label: i18n.create_child_map || "Create child map",
    disabled: !zone.name || zone.name.trim() === "",
    tooltip: !zone.name ? (i18n.name_zone_first || "Name the zone first") : null,
    action: () => hook.pushEvent("create_child_map_from_zone", { zone_id: String(zoneId) }),
  });
}
```

**Note:** `i18n.create_child_map` and `i18n.name_zone_first` must be added to the i18n
strings pushed from the server in `show.ex` (same pattern as existing `i18n.duplicate` etc.).

The `disabled` + `tooltip` pattern follows existing context menu conventions —
`context_menu.js` already supports `disabled` items rendering as greyed out.

### Part 2b: Server-side event handler

#### `lib/storyarn_web/live/map_live/show.ex`

```elixir
def handle_event("create_child_map_from_zone", params, socket) do
  with_auth(socket, :edit_content, fn ->
    TreeHandlers.handle_create_child_map_from_zone(params, socket)
  end)
end
```

#### `lib/storyarn_web/live/map_live/handlers/tree_handlers.ex`

New function `handle_create_child_map_from_zone/2`:

```elixir
def handle_create_child_map_from_zone(%{"zone_id" => zone_id}, socket) do
  map = socket.assigns.map

  with zone when not is_nil(zone) <- Maps.get_zone(map.id, zone_id),
       :ok <- validate_zone_has_name(zone),
       {:ok, bg_asset} <- extract_zone_background(map, zone, socket.assigns.project),
       child_attrs <- build_child_map_attrs(zone, map, bg_asset),
       {:ok, child_map} <- Maps.create_map(socket.assigns.project, child_attrs),
       {:ok, _updated_zone} <- Maps.update_zone(zone, %{target_type: "map", target_id: child_map.id}) do
    {:noreply,
     push_navigate(socket,
       to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{child_map.id}"
     )}
  else
    nil ->
      {:noreply, put_flash(socket, :error, dgettext("maps", "Zone not found."))}
    {:error, :zone_has_no_name} ->
      {:noreply, put_flash(socket, :error, dgettext("maps", "Name the zone before creating a child map."))}
    {:error, :no_background_image} ->
      create_child_map_without_image(zone, map, socket)
    {:error, :image_extraction_failed} ->
      create_child_map_without_image(zone, map, socket)
    {:error, _} ->
      {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create child map."))}
  end
end

defp validate_zone_has_name(%{name: nil}), do: {:error, :zone_has_no_name}
defp validate_zone_has_name(%{name: ""}), do: {:error, :zone_has_no_name}
defp validate_zone_has_name(_zone), do: :ok

defp create_child_map_without_image(zone, map, socket) do
  child_attrs = build_child_map_attrs(zone, map, nil)

  case Maps.create_map(socket.assigns.project, child_attrs) do
    {:ok, child_map} ->
      Maps.update_zone(zone, %{target_type: "map", target_id: child_map.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("maps", "Child map created. Add a background image to continue."))
       |> push_navigate(
         to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{child_map.id}"
       )}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create child map."))}
  end
end
```

### Part 2c: Image extraction pipeline

#### `lib/storyarn/maps/zone_image_extractor.ex` (new file)

```elixir
defmodule Storyarn.Maps.ZoneImageExtractor do
  @moduledoc """
  Extracts a cropped + upscaled image fragment from a parent map's
  background image, bounded to a zone's vertex bounding box.

  Returns {:ok, %Asset{}} on success.
  Returns {:error, :no_background_image} when the parent map has no background.
  Returns {:error, :image_extraction_failed} on processing failures.
  """

  require Logger

  alias Storyarn.Assets
  alias Storyarn.Assets.Storage
  alias Storyarn.Maps.MapZone

  @upscale_factor 2.0
  @upscale_kernel :lanczos3

  @doc """
  Extracts a zone's bounding-box region from the parent map's background image,
  upscales it 2×, uploads it to storage, and returns the new Asset.
  """
  def extract(parent_map, %MapZone{} = zone, project) do
    with {:ok, asset} <- get_background_asset(parent_map),
         {:ok, img} <- open_image(asset),
         {:ok, cropped} <- crop_to_zone(img, zone),
         {:ok, upscaled} <- upscale(cropped),
         {:ok, temp_path} <- write_temp(upscaled),
         {:ok, uploaded_asset} <- upload_and_create_asset(temp_path, zone.name, project) do
      cleanup_temp(temp_path)
      {:ok, uploaded_asset}
    else
      {:error, :no_background_image} = err ->
        err

      {:error, reason} ->
        Logger.warning("[ZoneImageExtractor] Failed: #{inspect(reason)}")
        {:error, :image_extraction_failed}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_background_asset(%{background_asset_id: nil}), do: {:error, :no_background_image}
  defp get_background_asset(%{background_asset: %{url: url}} = _map) when is_binary(url) do
    {:ok, %{url: url}}
  end
  defp get_background_asset(map) do
    case Assets.get_asset(map.background_asset_id) do
      nil -> {:error, :no_background_image}
      asset -> {:ok, asset}
    end
  end

  defp open_image(%{url: url}) do
    case Image.open(url) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:open_failed, reason}}
    end
  end

  defp crop_to_zone(img, zone) do
    # Zone vertices use string keys from JSONB (e.g. %{"x" => 10.5, "y" => 20.0})
    {min_x, min_y, max_x, max_y} = bounding_box(zone.vertices)

    {img_w, img_h} = {Image.width(img), Image.height(img)}

    left   = round(min_x / 100.0 * img_w)
    top    = round(min_y / 100.0 * img_h)
    crop_w = max(1, round((max_x - min_x) / 100.0 * img_w))
    crop_h = max(1, round((max_y - min_y) / 100.0 * img_h))

    Image.crop(img, left, top, crop_w, crop_h)
  end

  defp upscale(img) do
    Image.resize(img, @upscale_factor, kernel: @upscale_kernel)
  end

  defp write_temp(img) do
    path = Path.join(System.tmp_dir!(), "zone_extract_#{System.unique_integer([:positive])}.webp")

    case Image.write(img, path) do
      {:ok, _} -> {:ok, path}
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end

  @doc false
  def upload_and_create_asset(temp_path, zone_name, project) do
    filename = Assets.sanitize_filename("#{zone_name}_extract.webp")
    key = Assets.generate_key(project, filename)
    binary_data = File.read!(temp_path)
    content_type = "image/webp"

    with {:ok, url} <- Storage.upload(key, binary_data, content_type),
         {:ok, asset} <-
           Assets.create_asset(project, %{
             filename: filename,
             content_type: content_type,
             size: byte_size(binary_data),
             key: key,
             url: url
           }) do
      {:ok, asset}
    end
  end

  defp cleanup_temp(path) do
    File.rm(path)
  rescue
    _ -> :ok
  end

  @doc "Computes the bounding box of zone vertices as {min_x, min_y, max_x, max_y}."
  def bounding_box(vertices) do
    # Vertices are stored as JSONB maps with string keys: %{"x" => float, "y" => float}
    xs = Enum.map(vertices, &access_coord(&1, "x"))
    ys = Enum.map(vertices, &access_coord(&1, "y"))
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  # Handle both string-keyed maps (from JSONB) and atom-keyed maps (from tests)
  defp access_coord(%{"x" => x}, "x"), do: x
  defp access_coord(%{"y" => y}, "y"), do: y
  defp access_coord(%{x: x}, "x"), do: x
  defp access_coord(%{y: y}, "y"), do: y
end
```

**Key differences from the previous version:**
- Uses the real upload pipeline: `Storage.upload/3` → `Assets.create_asset/2` (matches
  the pattern in `asset_live/index.ex:do_upload/4`)
- No invalid `with/after` syntax — uses explicit `cleanup_temp/1` on success path
  and `Logger.warning` on error path
- Handles both string-keyed and atom-keyed vertex maps for robustness
- `bounding_box/1` is `def` (public) for unit testing

### Part 2d: Scale inheritance formula

```elixir
# In tree_handlers.ex

defp build_child_map_attrs(zone, parent_map, bg_asset) do
  {min_x, _min_y, max_x, _max_y} = ZoneImageExtractor.bounding_box(zone.vertices)
  bw_percent = max_x - min_x

  child_scale =
    if parent_map.scale_value && bw_percent > 0,
      do: parent_map.scale_value * bw_percent / 100.0,
      else: nil

  %{
    name: zone.name,
    parent_id: parent_map.id,
    background_asset_id: bg_asset && bg_asset.id,
    scale_value: child_scale,
    scale_unit: parent_map.scale_unit
  }
end

defp extract_zone_background(map, zone, project) do
  ZoneImageExtractor.extract(map, zone, project)
end
```

**Formula rationale:** `scale_value` represents the total real-world distance of the
full map width (100%). The zone spans `bw_percent` of that width, so:
```
child scale_value = parent.scale_value × bw_percent / 100
```
The child map's image is a 2× upscale of the crop, but it still represents the same
physical area — only the resolution changes, not the scale.

### Part 2e: Breadcrumb in the header

#### `lib/storyarn/maps/map_crud.ex`

Add a function to load the ancestor chain:

```elixir
@doc "Returns ancestors from root to direct parent, ordered top-down."
def list_ancestors(map) do
  do_collect_ancestors(map.parent_id, [])
end

defp do_collect_ancestors(nil, acc), do: acc

defp do_collect_ancestors(parent_id, acc) do
  case Repo.get(Map, parent_id) do
    nil -> acc
    parent -> do_collect_ancestors(parent.parent_id, [parent | acc])
  end
end
```

This uses simple recursive DB reads. For typical map hierarchies (< 10 levels deep)
this is fast enough. A recursive CTE would be faster for deeper trees but adds complexity.

Delegate via `lib/storyarn/maps.ex`:
```elixir
defdelegate list_ancestors(map), to: MapCrud
```

#### `lib/storyarn_web/live/map_live/show.ex`

Load ancestors on mount and `handle_params`:

```elixir
|> assign(:ancestors, Maps.list_ancestors(map))
```

#### `lib/storyarn_web/live/map_live/components/map_header.ex`

Add `ancestors` attr and a breadcrumb nav before the editable title.

The breadcrumb uses `Enum.with_index` to place separators correctly (N-1 separators
for N ancestors):

```elixir
attr :ancestors, :list, default: []

# In the template, inside the flex-1 div (line 33), BEFORE the existing <div> with <h1>:
<nav :if={@ancestors != []} class="flex items-center gap-1 text-sm text-base-content/50 mb-0.5">
  <span :for={{ancestor, idx} <- Enum.with_index(@ancestors)}>
    <span :if={idx > 0} class="opacity-50">/</span>
    <.link
      navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{ancestor.id}"}
      class="hover:text-base-content truncate max-w-[120px]"
    >
      {ancestor.name}
    </.link>
  </span>
  <span class="opacity-50">/</span>
</nav>
```

This renders: `Root / Middle / ` before the current map title (the final `/` separates
the last ancestor from the current map name shown in the `<h1>`).

### Corner Cases

| Case | What happens | How to handle |
|------|-------------|---------------|
| **Zone has no name** | Child map name would be empty | Context menu item greyed out with tooltip *"Name the zone first"*. Server also validates and returns error flash. |
| **Zone already links to a map** | Would silently overwrite `target_id` | Show confirmation: *"This zone already links to [map name]. Replace it?"* (re-use existing confirm_modal pattern) |
| **Parent has no background image** | Nothing to crop | Skip image extraction, create child map without background, flash info: *"Child map created. Add a background image to continue."* |
| **Image extraction fails** (network, corrupt file, format unsupported) | `ZoneImageExtractor.extract/3` returns `{:error, :image_extraction_failed}` | Create child map without background (same as above), log error server-side |
| **Zone is moved or resized after child creation** | Child background image is a stale snapshot | In the zone properties panel, when `target_type == "map"`, show a small info note: *"Background image is a snapshot taken at creation."* (re-extract button deferred to follow-up) |
| **Zone is deleted from parent** | Child map remains accessible via sidebar (`parent_id` intact) | On zone delete confirmation modal, add: *"This zone links to child map [name]. The child map will remain but will no longer be accessible by clicking this zone."* |
| **Parent map image is replaced after child creation** | Child background becomes outdated | Same as zone moved/resized — it's a snapshot, no automatic sync |
| **Zone has < 3 vertices** | DB validation prevents this, but just in case | Guard in handler: `if length(zone.vertices) < 3, do: error` |
| **Concurrent creation** | Two editors click simultaneously | `Maps.create_map/2` is idempotent per call — two child maps would be created. Acceptable edge case for now (real-time collaboration is deferred) |

### Tests

New `describe` block in `test/storyarn_web/live/map_live/show_test.exs`:

```
describe "create_child_map_from_zone event" do
  - creates child map with zone name and parent_id = current map
  - zone target_type updated to "map", target_id = new child map id
  - navigates to child map after creation
  - zone with no name returns error flash, no map created
  - zone not found returns error flash
  - viewer cannot trigger event (auth guard)
  - zone already linked to map: replaces target after confirmation
  - map without background: creates child without background (no error)
end
```

New unit tests in `test/storyarn/maps_test.exs`:

```
describe "ZoneImageExtractor.bounding_box/1" do
  - returns correct {min_x, min_y, max_x, max_y} from vertices
  - handles both string-keyed and atom-keyed maps
end

describe "ZoneImageExtractor.extract/3" do
  - returns {:error, :no_background_image} when map has no background
end

describe "list_ancestors/1" do
  - returns [] for root map
  - returns [root] for depth-1 map
  - returns [root, mid] for depth-2 map (ordered top-down)
end
```

### Files created/modified

```
NEW:  lib/storyarn/maps/zone_image_extractor.ex
MOD:  lib/storyarn/maps/map_crud.ex          — list_ancestors/1
MOD:  lib/storyarn/maps.ex                   — defdelegate list_ancestors
MOD:  lib/storyarn_web/live/map_live/show.ex — event handler + ancestors assign
MOD:  lib/storyarn_web/live/map_live/handlers/tree_handlers.ex — handler impl
MOD:  lib/storyarn_web/live/map_live/components/map_header.ex  — breadcrumb
MOD:  assets/js/map_canvas/handlers/zone_handler.js            — context menu item
MOD:  test/storyarn_web/live/map_live/show_test.exs
MOD:  test/storyarn/maps_test.exs
```

### Verification

```bash
mix test test/storyarn/maps_test.exs test/storyarn_web/live/map_live/show_test.exs
mix credo --strict
```

---

## Task D3: Path Labels Following Connection Curvature

### Problem

Connection `label` already exists in the schema and is editable in the properties panel,
but it is never rendered on the canvas. The label should appear along the connection line,
following its curvature when waypoints create a curved path.

### Solution: `leaflet-textpath`

Use the [`leaflet-textpath`](https://github.com/makinacorpus/Leaflet.TextPath) plugin.
It extends `L.Polyline` with a `.setText()` method that renders text following the path,
including curved paths.

**Why not hand-roll SVG `<textPath>`:** The polyline's SVG `<path>` element ID is managed
internally by Leaflet and changes on redraw. `leaflet-textpath` handles this correctly.

**Compatibility with leaflet-polylinedecorator:** These two plugins are safe to use on the
same polyline. `leaflet-textpath` works by injecting SVG `<text>` + `<textPath>` elements
into the polyline's `<path>`, while `leaflet-polylinedecorator` creates separate `L.Layer`
objects as overlays. They modify different DOM structures and do not conflict.

### New dependency

```bash
cd assets && npm install leaflet-textpath
```

### Implementation

#### `assets/js/map_canvas/connection_renderer.js`

```js
// Add import at top (after existing leaflet-polylinedecorator imports, line 12):
import "leaflet-textpath";

// In createConnectionLine (after line 47, before `return line`):
applyLabel(line, conn.label, conn.color);

// In updateConnectionLine (after replaceArrows at line 65):
applyLabel(line, conn.label, conn.color);

// New private helper:
/**
 * Applies or clears text along a connection polyline.
 *
 * IMPORTANT: setText() does NOT clear previous text when updating (known bug
 * makinacorpus/Leaflet.TextPath#78). Must call setText(null) first.
 *
 * setText() auto-re-renders when setLatLngs() is called (hooks into _updatePath),
 * so waypoint drags update the text position automatically.
 */
function applyLabel(line, label, color) {
  const text = label && label.trim() !== "" ? label.trim() : null;

  // Always clear first (bug #78: setText doesn't erase previous text)
  line.setText(null);

  if (text) {
    line.setText(text, {
      repeat: false,
      below: false,
      offset: 6,
      orientation: "auto",  // keeps text upright (never upside-down)
      attributes: {
        "font-size": "11",
        "font-weight": "600",
        fill: color || DEFAULT_COLOR,
        stroke: "white",
        "stroke-width": "3",
        "paint-order": "stroke fill",  // white stroke behind colored fill for legibility
      },
    });
  }
}
```

The `"paint-order": "stroke fill"` trick renders a white stroke behind the colored text,
making it legible on both dark and light backgrounds without needing a background box.

#### `assets/js/map_canvas/handlers/connection_handler.js`

No changes needed — `updateConnectionLine` already calls `connection_renderer.js`.

The `setText()` method hooks into `L.Polyline.prototype._updatePath`, so when waypoints
are dragged and `line.setLatLngs()` is called (in `updateLineFromHandles`, line 389),
the text automatically re-renders along the new path.

### Behavior

- Straight path (no waypoints): label appears at path midpoint, horizontal
- Curved path (waypoints): label follows the curvature
- `orientation: "auto"`: Leaflet.TextPath rotates the text per-segment so it never
  appears upside-down (always readable left-to-right)
- When connection is updated (label or waypoints change): text re-renders automatically
- When label is cleared: text removed from path via `setText(null)`
- Waypoint drag: text follows new geometry in real-time (via `_updatePath` hook)

### Tests

No server-side changes — `connection.label` is already stored and serialized.
The Label input in `element_panels.ex` already pushes `update_connection`. Pure JS.

Manual verification:
- Connection with label → text visible along line
- Curved path (waypoints) → text follows curvature
- Label update in properties panel → text updates on canvas
- Clearing label → text disappears
- Waypoint drag → text re-renders along new geometry
- Both arrows AND label visible simultaneously (no conflicts)

### Files modified

```
MOD:  assets/package.json (+ package-lock.json) — new dep: leaflet-textpath
MOD:  assets/js/map_canvas/connection_renderer.js — import + applyLabel helper + calls
```

### Verification

```bash
cd assets && npm install
mix credo --strict
```

---

## Task D4: "Appears on Maps" in Sheet References Tab

### Problem

`ReferencesTab` contains `VariableUsageSection` + `BacklinksSection` but no section showing
which maps reference this sheet (via pins or zones with `target_type: "sheet"`).

### What already exists

- `Maps.get_elements_for_target("sheet", sheet_id)` returns `%{zones: [...], pins: [...]}`
  with `map` preloaded on each. Tested in `maps_test.exs`. Do NOT duplicate this.
- `BacklinksSection` — use as structural pattern (lazy-loading LiveComponent).
- `ReferencesTab` already receives `@workspace` and `@project` via assigns pass-through
  in its `update/2` callback.

### New file: `lib/storyarn_web/live/sheet_live/components/map_appearances_section.ex`

LiveComponent following the exact `BacklinksSection` pattern:
- `assign_new(:appearances, fn -> nil end)` on update
- `load_appearances/1` calls `Maps.get_elements_for_target("sheet", sheet.id)`
  and flattens `%{zones: zones, pins: pins}` into:
  ```elixir
  [%{element_type: "pin"|"zone", element_name: ..., map_id: ..., map_name: ...}, ...]
  ```
- Each row: map icon + map name (link to map) + badge "Pin"/"Zone" + element name
- Empty state: *"This sheet doesn't appear on any maps yet."*
- The link to the map uses the full path:
  `~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{map_id}"`

### Modified: `lib/storyarn_web/live/sheet_live/components/references_tab.ex`

Add alias + `<.live_component module={MapAppearancesSection} .../>` after BacklinksSection.
Pass `workspace` and `project` (already available in `ReferencesTab` assigns).

### Tests

New `describe` block in `test/storyarn_web/live/sheet_live/show_test.exs`:

```
describe "References tab — map appearances" do
  - renders section heading "Appears on Maps"
  - shows pin appearance when sheet is referenced by a pin's target_id
  - shows zone appearance when sheet is referenced by a zone's target_id
  - shows count badge when appearances exist
  - shows empty state when sheet has no map appearances
  - "View on Map" link navigates to correct map URL
end
```

### Files created/modified

```
NEW:  lib/storyarn_web/live/sheet_live/components/map_appearances_section.ex
MOD:  lib/storyarn_web/live/sheet_live/components/references_tab.ex — add third section
MOD:  test/storyarn_web/live/sheet_live/show_test.exs
```

### Verification

```bash
mix test test/storyarn_web/live/sheet_live/show_test.exs
mix credo --strict
```

---

## Task D5: Pins and Zones as Children in Sidebar Tree

### Problem

The sidebar map tree shows the map hierarchy but not the elements inside each map.
Originally blocked by "requires canvas phase" — canvas is now complete.

### Design decision: Option A with cap

Show zones and pins as children of each map, capped at 10 per type.
If a map has more, show a non-clickable summary: *"3 more zones…"*

```
World Map
├── ◇ Northern Kingdom    ← zone (link: /maps/1?highlight=zone:42)
├── ○ Capital City        ← pin  (link: /maps/1?highlight=pin:7)
└── Northern Kingdom      ← child map
    └── ○ The Palace      ← pin
```

### Changes needed

#### `lib/storyarn/maps/map_crud.ex`

Add `list_maps_tree_with_elements/1` that loads maps + limited elements:

```elixir
@sidebar_element_limit 10

def list_maps_tree_with_elements(project_id) do
  all_maps =
    from(m in Map,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name]
    )
    |> Repo.all()

  map_ids = Enum.map(all_maps, & &1.id)

  # Load limited zones and pins per map in two bulk queries
  zones_by_map = load_sidebar_zones(map_ids)
  pins_by_map = load_sidebar_pins(map_ids)
  zone_counts = count_elements_by_map(MapZone, map_ids)
  pin_counts = count_elements_by_map(MapPin, map_ids)

  all_maps =
    Enum.map(all_maps, fn map ->
      map
      |> Elixir.Map.put(:sidebar_zones, Elixir.Map.get(zones_by_map, map.id, []))
      |> Elixir.Map.put(:sidebar_pins, Elixir.Map.get(pins_by_map, map.id, []))
      |> Elixir.Map.put(:zone_count, Elixir.Map.get(zone_counts, map.id, 0))
      |> Elixir.Map.put(:pin_count, Elixir.Map.get(pin_counts, map.id, 0))
    end)

  build_tree(all_maps)
end

# Loads up to @sidebar_element_limit zones per map, ordered by position
defp load_sidebar_zones(map_ids) do
  from(z in MapZone,
    where: z.map_id in ^map_ids and is_nil(z.deleted_at),
    where: not is_nil(z.name) and z.name != "",
    order_by: [asc: z.position, asc: z.name],
    select: %{id: z.id, name: z.name, map_id: z.map_id,
              row: over(row_number(), partition_by: z.map_id, order_by: [asc: z.position])}
  )
  |> subquery()
  |> where([s], s.row <= ^@sidebar_element_limit)
  |> Repo.all()
  |> Enum.group_by(& &1.map_id)
end

# Same pattern for pins
defp load_sidebar_pins(map_ids) do
  from(p in MapPin,
    where: p.map_id in ^map_ids and is_nil(p.deleted_at),
    order_by: [asc: p.position, asc: p.label],
    select: %{id: p.id, label: p.label, map_id: p.map_id,
              row: over(row_number(), partition_by: p.map_id, order_by: [asc: p.position])}
  )
  |> subquery()
  |> where([s], s.row <= ^@sidebar_element_limit)
  |> Repo.all()
  |> Enum.group_by(& &1.map_id)
end

defp count_elements_by_map(schema, map_ids) do
  from(e in schema,
    where: e.map_id in ^map_ids and is_nil(e.deleted_at),
    group_by: e.map_id,
    select: {e.map_id, count(e.id)}
  )
  |> Repo.all()
  |> Elixir.Map.new()
end
```

Delegate via `maps.ex`:
```elixir
defdelegate list_maps_tree_with_elements(project_id), to: MapCrud
```

#### `lib/storyarn_web/components/sidebar/map_tree.ex`

**Key change:** A map that has no child maps but DOES have zones/pins must now render
as a `tree_node` (expandable) instead of a `tree_leaf`. Update `has_children` logic:

```elixir
def map_tree_items(assigns) do
  has_child_maps = TreeHelpers.has_children?(assigns.map)
  has_elements = (assigns.map[:sidebar_zones] || []) != [] or
                 (assigns.map[:sidebar_pins] || []) != []
  has_children = has_child_maps or has_elements
  # ... rest of assigns
end
```

Inside the `tree_node` children block, after rendering child maps, render element leaves:

```elixir
<%!-- Zone leaves --%>
<.tree_leaf
  :for={zone <- Map.get(@map, :sidebar_zones, [])}
  label={zone.name}
  icon="pentagon"
  href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{@map.id}?highlight=zone:#{zone.id}"}
  active={false}
  item_id={"zone-#{zone.id}"}
  item_name={zone.name}
  can_drag={false}
/>
<div
  :if={Map.get(@map, :zone_count, 0) > length(Map.get(@map, :sidebar_zones, []))}
  class="text-xs text-base-content/40 pl-8 py-0.5"
>
  {dngettext("maps", "%{count} more zone…", "%{count} more zones…",
    Map.get(@map, :zone_count, 0) - length(Map.get(@map, :sidebar_zones, [])),
    count: Map.get(@map, :zone_count, 0) - length(Map.get(@map, :sidebar_zones, []))
  )}
</div>

<%!-- Pin leaves --%>
<.tree_leaf
  :for={pin <- Map.get(@map, :sidebar_pins, [])}
  label={pin.label || dgettext("maps", "Pin")}
  icon="map-pin"
  href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{@map.id}?highlight=pin:#{pin.id}"}
  active={false}
  item_id={"pin-#{pin.id}"}
  item_name={pin.label || ""}
  can_drag={false}
/>
<div
  :if={Map.get(@map, :pin_count, 0) > length(Map.get(@map, :sidebar_pins, []))}
  class="text-xs text-base-content/40 pl-8 py-0.5"
>
  {dngettext("maps", "%{count} more pin…", "%{count} more pins…",
    Map.get(@map, :pin_count, 0) - length(Map.get(@map, :sidebar_pins, [])),
    count: Map.get(@map, :pin_count, 0) - length(Map.get(@map, :sidebar_pins, []))
  )}
</div>
```

#### `lib/storyarn_web/live/map_live/show.ex`

1. Change `list_maps_tree` call to `list_maps_tree_with_elements` in mount/reload.

2. Handle `?highlight` query param in `handle_params/3`. Use a one-shot approach:
   only push the event if `highlight` param is present, then the JS handler consumes it
   (no need to clear — `handle_params` only fires on navigation, not on re-renders):

```elixir
socket =
  case params["highlight"] do
    "pin:" <> id -> push_event(socket, "highlight_element", %{type: "pin", id: id})
    "zone:" <> id -> push_event(socket, "highlight_element", %{type: "zone", id: id})
    _ -> socket
  end
```

#### `assets/js/hooks/map_canvas.js`

Handle `highlight_element` server event. Use existing handler infrastructure:

```js
this.handleEvent("highlight_element", ({ type, id }) => {
  const numId = parseInt(id, 10);
  if (isNaN(numId)) return;

  // Select the element (same as clicking)
  this.pushEvent("select_element", { type, id: numId });

  // Pan/zoom to it
  if (type === "zone" && this.zoneHandler) {
    this.zoneHandler.focusZone(numId);  // already exists (line 594)
  } else if (type === "pin" && this.pinHandler) {
    this.pinHandler.focusPin(numId);    // may need to add if not present
  }
});
```

Note: `zoneHandler.focusZone` already exists (line 594 of `zone_handler.js`).
Check if `pinHandler.focusPin` exists; if not, add it following the same pattern
(`flyTo` on the marker's latlng).

### Tests

```
describe "highlight query param" do
  - ?highlight=pin:ID pushes highlight_element JS event with type=pin
  - ?highlight=zone:ID pushes highlight_element JS event with type=zone
  - invalid or missing highlight param is ignored (no push_event)
end

describe "sidebar tree with elements" do
  - maps with zones show zone leaves in sidebar
  - maps with pins show pin leaves in sidebar
  - maps with >10 zones show "N more zones…" summary
  - maps with no elements render as tree_leaf (no expand arrow)
end
```

### Files modified

```
MOD:  lib/storyarn/maps/map_crud.ex — list_maps_tree_with_elements + queries
MOD:  lib/storyarn/maps.ex — defdelegate
MOD:  lib/storyarn_web/components/sidebar/map_tree.ex — element leaves + has_children logic
MOD:  lib/storyarn_web/live/map_live/show.ex — highlight param + tree function swap
MOD:  assets/js/hooks/map_canvas.js — highlight_element event handler
MOD:  test/storyarn_web/live/map_live/show_test.exs
```

### Verification

```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo --strict
```

---

## Task Dependency Graph

```
D1 (zone label on canvas)           ← no dependencies
D2 (zone → child map)               ← D1 (label must be visible first)
D3 (path labels on connections)     ← no dependencies
D4 (sheet "appears on maps")        ← no dependencies
D5 (sidebar tree elements)          ← no dependencies
```

D1 and D2 must be done in order. D3, D4, D5 are independent.

---

## Execution Workflow

```
Per task:
  mix compile --warnings-as-errors   ← after each file modified
  mix credo --strict                 ← after each file modified
  mix test                           ← after each task complete

Final:
  mix test
  mix credo --strict --all
  find lib -name "*.ex" | xargs wc -l | sort -rn | head -20
```

---

## Open Questions (decide before implementing D2)

1. **Image extraction: sync or async?**
   Cropping + upscaling can take 1–3 seconds for large images. Should this happen:
   - **Synchronously in the LiveView process** (simple, blocks the socket temporarily): acceptable
     for infrequent action; user sees spinner or is navigated away before it finishes
   - **Via Task.async_nolink** (non-blocking, notify via `handle_info`): better UX, slightly
     more complex
   - **Via a background job (Oban)**: overkill for this use case

   Recommendation: synchronous first. Add async if it proves too slow in practice.

2. **Re-extract after zone edit?**
   Should the zone properties panel show a "Re-extract map from zone" button when the zone
   already has a linked child map? This would re-run the image extraction pipeline.
   Recommendation: add as a Phase D2 follow-up (a second button in the target_selector
   when `target_type == "map"` and a child map exists).

3. **Zone name required?**
   Block the context menu item entirely (greyed out with tooltip) or show error after click?
   Recommendation: grey out with tooltip "Name the zone first" — clearer UX.
   (Both client-side disabled state AND server-side validation for safety.)
