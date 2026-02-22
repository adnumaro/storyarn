/**
 * InteractionPlayer hook — renders a map with clickable zones in the Story Player.
 *
 * Data attributes:
 * - data-background-url: Map background image URL
 * - data-map-width / data-map-height: Original map dimensions
 * - data-zones: JSON array of zone objects
 * - data-variables: JSON object of display variable values {ref: value}
 *
 * Zone action types:
 * - instruction: Clickable, pushes "interaction_zone_instruction"
 * - display: Shows label + current variable value
 * - event: Clickable, pushes "interaction_zone_event"
 * - navigate: Inert in player context
 */
export const InteractionPlayer = {
  mounted() {
    this.backgroundUrl = this.el.dataset.backgroundUrl;
    this.mapWidth = parseInt(this.el.dataset.mapWidth, 10) || 800;
    this.mapHeight = parseInt(this.el.dataset.mapHeight, 10) || 600;
    this.zones = JSON.parse(this.el.dataset.zones || "[]");
    this.variables = JSON.parse(this.el.dataset.variables || "{}");

    this.render();

    this.handleEvent("interaction_variables_updated", ({ variables }) => {
      this.variables = variables;
      this.updateDisplayZones();
    });
  },

  render() {
    // Clear any server-rendered fallback content
    this.el.innerHTML = "";

    // Create wrapper with correct aspect ratio
    const wrapper = document.createElement("div");
    wrapper.className = "interaction-map-wrapper";
    wrapper.style.position = "relative";
    wrapper.style.width = "100%";
    wrapper.style.maxWidth = "640px";
    wrapper.style.aspectRatio = `${this.mapWidth} / ${this.mapHeight}`;
    wrapper.style.margin = "0 auto";
    wrapper.style.overflow = "hidden";
    wrapper.style.borderRadius = "0.5rem";

    // Background image
    if (this.backgroundUrl) {
      const img = document.createElement("img");
      img.src = this.backgroundUrl;
      img.alt = "Map";
      img.style.position = "absolute";
      img.style.inset = "0";
      img.style.width = "100%";
      img.style.height = "100%";
      img.style.objectFit = "contain";
      img.draggable = false;
      wrapper.appendChild(img);
    }

    // Render zones
    for (const zone of this.zones) {
      const zoneEl = this.createZoneElement(zone);
      if (zoneEl) wrapper.appendChild(zoneEl);
    }

    this.el.appendChild(wrapper);
  },

  createZoneElement(zone) {
    const { vertices, action_type } = zone;
    if (!vertices || vertices.length < 3) return null;

    const div = document.createElement("div");
    div.className = `interaction-zone interaction-zone-${action_type}`;
    div.dataset.zoneId = zone.id;
    div.dataset.actionType = action_type;

    // Full-size overlay clipped to polygon shape
    div.style.position = "absolute";
    div.style.inset = "0";
    div.style.clipPath = `polygon(${vertices.map((v) => `${v.x}% ${v.y}%`).join(", ")})`;

    // Fill color with opacity
    const fillColor = zone.fill_color || "#3b82f6";
    const opacity = zone.opacity != null ? zone.opacity : 0.3;
    div.style.backgroundColor = fillColor;
    div.style.opacity = opacity;

    // Border via outline doesn't work with clip-path, so skip visual border

    // Centered label using bounding box
    const bbox = this.getBoundingBox(vertices);
    const labelContainer = document.createElement("div");
    labelContainer.style.position = "absolute";
    labelContainer.style.left = `${bbox.minX}%`;
    labelContainer.style.top = `${bbox.minY}%`;
    labelContainer.style.width = `${bbox.maxX - bbox.minX}%`;
    labelContainer.style.height = `${bbox.maxY - bbox.minY}%`;
    labelContainer.style.display = "flex";
    labelContainer.style.flexDirection = "column";
    labelContainer.style.alignItems = "center";
    labelContainer.style.justifyContent = "center";
    labelContainer.style.pointerEvents = "none";

    if (action_type === "display") {
      const ref = zone.action_data?.variable_ref;
      const label = document.createElement("span");
      label.className = "zone-display-label";
      label.textContent = zone.name;
      labelContainer.appendChild(label);

      const value = document.createElement("span");
      value.className = "zone-display-value";
      if (ref) value.dataset.ref = ref;
      value.textContent = this.variables[ref] ?? "—";
      labelContainer.appendChild(value);
    } else {
      const label = document.createElement("span");
      label.className = "zone-label";
      label.textContent = zone.name;
      labelContainer.appendChild(label);
    }

    // Clickable zones
    if (action_type === "instruction") {
      div.style.cursor = "pointer";
      div.addEventListener("click", () => {
        const assignments = zone.action_data?.assignments || [];
        this.pushEvent("interaction_zone_instruction", {
          zone_id: zone.id,
          zone_name: zone.name,
          assignments: assignments,
        });
      });
    } else if (action_type === "event") {
      div.style.cursor = "pointer";
      const eventName = zone.action_data?.event_name || `zone_${zone.id}`;
      div.addEventListener("click", () => {
        this.pushEvent("interaction_zone_event", {
          zone_id: zone.id,
          event_name: eventName,
        });
      });
    }

    // Group zone overlay + label in a fragment-like wrapper
    const group = document.createElement("div");
    group.style.position = "absolute";
    group.style.inset = "0";
    group.appendChild(div);
    group.appendChild(labelContainer);

    return group;
  },

  getBoundingBox(vertices) {
    let minX = 100,
      minY = 100,
      maxX = 0,
      maxY = 0;
    for (const v of vertices) {
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }
    return { minX, minY, maxX, maxY };
  },

  updateDisplayZones() {
    const displayValues = this.el.querySelectorAll(".zone-display-value[data-ref]");
    for (const el of displayValues) {
      const ref = el.dataset.ref;
      el.textContent = this.variables[ref] ?? "—";
    }
  },
};
