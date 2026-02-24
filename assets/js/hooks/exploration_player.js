/**
 * ExplorationPlayer hook — renders a scene with clickable zones and pins
 * for the exploration mode player.
 *
 * Data attributes:
 * - data-exploration: JSON object containing:
 *   { background_url, scene_width, scene_height, zones[], pins[] }
 *
 * Zone/pin action types:
 * - instruction: Clickable, pushes "exploration_instruction"
 * - display: Shows label + current variable value
 * - none/navigate: Zones with target_type push "exploration_target_click"
 *
 * Visibility states:
 * - visible: Rendered normally
 * - hide: Not rendered
 * - disable: Rendered dimmed, not clickable
 */
import { createElement, MapPin, Star, User, Zap } from "lucide";

const PIN_ICONS = {
  location: MapPin,
  character: User,
  event: Zap,
  custom: Star,
};

export const ExplorationPlayer = {
  mounted() {
    const data = JSON.parse(this.el.dataset.exploration || "{}");
    this.backgroundUrl = data.background_url;
    this.sceneWidth = data.scene_width || 800;
    this.sceneHeight = data.scene_height || 600;
    this.zones = data.zones || [];
    this.pins = data.pins || [];
    this.variables = {};

    this.render();

    this.handleEvent("exploration_state_updated", ({ zones, pins, variables }) => {
      this.variables = variables || {};
      this.updateVisibility(zones, pins);
      this.updateDisplayZones();
    });
  },

  destroyed() {
    // Cleanup: nothing to do currently (DOM is removed on navigate)
  },

  render() {
    this.el.innerHTML = "";

    const wrapper = document.createElement("div");
    wrapper.className = "exploration-wrapper";
    wrapper.style.position = "relative";
    wrapper.style.width = "100%";
    wrapper.style.aspectRatio = `${this.sceneWidth} / ${this.sceneHeight}`;
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
      img.style.objectFit = "fill";
      img.draggable = false;

      const onLoad = () => {
        if (img.naturalWidth && img.naturalHeight) {
          wrapper.style.aspectRatio = `${img.naturalWidth} / ${img.naturalHeight}`;
        }
      };
      img.addEventListener("load", onLoad);
      if (img.complete && img.naturalWidth) onLoad();

      wrapper.appendChild(img);
    }

    // Render zones
    for (const zone of this.zones) {
      const el = this.createZoneElement(zone);
      if (el) wrapper.appendChild(el);
    }

    // Render pins
    for (const pin of this.pins) {
      const el = this.createPinElement(pin);
      if (el) wrapper.appendChild(el);
    }

    this.el.appendChild(wrapper);
  },

  createZoneElement(zone) {
    const { vertices, visibility } = zone;
    if (!vertices || vertices.length < 3) return null;
    if (visibility === "hide") return null;

    const isDisabled = visibility === "disable";
    const actionType = zone.action_type || "none";
    const hasTarget = zone.target_type && zone.target_id;
    const isClickable = !isDisabled && (actionType === "instruction" || hasTarget);

    // Zone overlay with clip-path
    const div = document.createElement("div");
    div.className = `interaction-zone interaction-zone-${actionType}`;
    div.dataset.zoneId = zone.id;
    div.style.position = "absolute";
    div.style.inset = "0";
    div.style.clipPath = `polygon(${vertices.map((v) => `${v.x}% ${v.y}%`).join(", ")})`;

    const fillColor = zone.fill_color || "#3b82f6";
    const opacity = zone.opacity != null ? zone.opacity : 0.3;
    div.style.backgroundColor = fillColor;
    div.style.opacity = isDisabled ? opacity * 0.3 : opacity;

    if (isClickable) {
      div.style.pointerEvents = "auto";
      div.style.cursor = "pointer";
    }

    // Click handler — single consolidated event
    if (isClickable) {
      div.addEventListener("click", () => {
        this.pushEvent("exploration_element_click", {
          element_type: "zone",
          element_id: zone.id,
          action_type: actionType,
          action_data: zone.action_data || {},
          target_type: zone.target_type || null,
          target_id: zone.target_id || null,
        });
      });
    }

    // Label container (centered in bounding box)
    const bbox = this.getBoundingBox(vertices);
    const labelContainer = document.createElement("div");
    labelContainer.dataset.role = "label-container";
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

    if (isDisabled) {
      labelContainer.style.opacity = "0.3";
    }

    if (actionType === "display") {
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

    // Group wrapper
    const group = document.createElement("div");
    group.style.position = "absolute";
    group.style.inset = "0";
    group.style.pointerEvents = "none";
    group.dataset.elementType = "zone";
    group.dataset.elementId = zone.id;
    group.appendChild(div);
    group.appendChild(labelContainer);

    return group;
  },

  createPinElement(pin) {
    const { visibility } = pin;
    if (visibility === "hide") return null;

    const isDisabled = visibility === "disable";
    const actionType = pin.action_type || "none";
    const hasTarget = pin.target_type && pin.target_id;
    const isClickable = !isDisabled && (actionType === "instruction" || hasTarget);

    const color = pin.color || "#3b82f6";
    const size = pin.size || "md";
    const iconSize = { sm: 16, md: 22, lg: 30 }[size] || 22;
    const markerSize = { sm: 28, md: 36, lg: 48 }[size] || 36;

    // Container positioned at pin coordinates
    const container = document.createElement("div");
    container.style.position = "absolute";
    container.style.left = `${pin.position_x}%`;
    container.style.top = `${pin.position_y}%`;
    container.style.transform = "translate(-50%, -50%)";
    container.style.display = "flex";
    container.style.flexDirection = "column";
    container.style.alignItems = "center";
    container.style.gap = "2px";
    container.style.zIndex = "10";
    container.dataset.elementType = "pin";
    container.dataset.elementId = pin.id;

    if (isDisabled) {
      container.style.opacity = "0.3";
      container.style.pointerEvents = "none";
    }

    // Pin marker (circle with icon or avatar)
    const marker = document.createElement("div");
    marker.style.width = `${markerSize}px`;
    marker.style.height = `${markerSize}px`;
    marker.style.borderRadius = "50%";
    marker.style.backgroundColor = color;
    marker.style.display = "flex";
    marker.style.alignItems = "center";
    marker.style.justifyContent = "center";
    marker.style.boxShadow = "0 2px 6px rgba(0,0,0,0.4)";
    marker.style.border = "2px solid rgba(255,255,255,0.6)";
    marker.style.transition = "transform 0.15s, box-shadow 0.15s";
    marker.style.flexShrink = "0";

    if (isClickable) {
      marker.style.cursor = "pointer";

      marker.addEventListener("mouseenter", () => {
        marker.style.transform = "scale(1.15)";
        marker.style.boxShadow = "0 3px 10px rgba(0,0,0,0.5)";
      });
      marker.addEventListener("mouseleave", () => {
        marker.style.transform = "scale(1)";
        marker.style.boxShadow = "0 2px 6px rgba(0,0,0,0.4)";
      });

      marker.addEventListener("click", () => {
        this.pushEvent("exploration_element_click", {
          element_type: "pin",
          element_id: pin.id,
          action_type: actionType,
          action_data: pin.action_data || {},
          target_type: pin.target_type || null,
          target_id: pin.target_id || null,
        });
      });
    }

    // Avatar or icon inside marker
    if (pin.avatar_url) {
      const avatar = document.createElement("img");
      avatar.src = pin.avatar_url;
      avatar.style.width = "100%";
      avatar.style.height = "100%";
      avatar.style.borderRadius = "50%";
      avatar.style.objectFit = "cover";
      avatar.draggable = false;
      marker.style.padding = "0";
      marker.style.overflow = "hidden";
      marker.appendChild(avatar);
    } else if (pin.icon_asset_url) {
      const icon = document.createElement("img");
      icon.src = pin.icon_asset_url;
      icon.style.width = `${iconSize}px`;
      icon.style.height = `${iconSize}px`;
      icon.style.objectFit = "contain";
      icon.draggable = false;
      marker.appendChild(icon);
    } else {
      const IconClass = PIN_ICONS[pin.pin_type] || PIN_ICONS.location;
      const iconEl = createElement(IconClass, {
        width: iconSize,
        height: iconSize,
        color: "#fff",
        strokeWidth: 2,
      });
      marker.appendChild(iconEl);
    }

    container.appendChild(marker);

    // Label below pin
    if (pin.label) {
      const label = document.createElement("span");
      label.className = "zone-label";
      label.style.fontSize = "10px";
      label.style.maxWidth = "80px";
      label.style.textAlign = "center";
      label.style.overflow = "hidden";
      label.style.textOverflow = "ellipsis";
      label.style.whiteSpace = "nowrap";
      label.textContent = pin.label;
      container.appendChild(label);
    }

    return container;
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

  updateVisibility(zones, pins) {
    const wrapper = this.el.querySelector(".exploration-wrapper");
    if (!wrapper) return;

    // Update zone visibility
    for (const zoneState of zones || []) {
      const group = wrapper.querySelector(
        `[data-element-type="zone"][data-element-id="${zoneState.id}"]`,
      );

      if (zoneState.visibility === "hide") {
        if (group) group.style.display = "none";
      } else if (zoneState.visibility === "disable") {
        if (group) {
          group.style.display = "";
          const overlay = group.querySelector(".interaction-zone");
          if (overlay) {
            overlay.style.opacity = "0.1";
            overlay.style.pointerEvents = "none";
            overlay.style.cursor = "default";
          }
          const labelContainer = group.querySelector('[data-role="label-container"]');
          if (labelContainer) labelContainer.style.opacity = "0.3";
        }
      } else {
        if (group) {
          group.style.display = "";
          const overlay = group.querySelector(".interaction-zone");
          if (overlay) {
            // Restore from original zone data
            const zone = this.zones.find((z) => String(z.id) === String(zoneState.id));
            if (zone) {
              overlay.style.opacity = zone.opacity != null ? zone.opacity : 0.3;
            }
            const actionType =
              overlay.dataset?.actionType || overlay.className.match(/interaction-zone-(\w+)/)?.[1];
            const hasTarget = zone?.target_type && zone?.target_id;
            if (actionType === "instruction" || hasTarget) {
              overlay.style.pointerEvents = "auto";
              overlay.style.cursor = "pointer";
            }
          }
          const labelContainer = group.querySelector('[data-role="label-container"]');
          if (labelContainer) labelContainer.style.opacity = "1";
        }
      }
    }

    // Update pin visibility
    for (const pinState of pins || []) {
      const el = wrapper.querySelector(
        `[data-element-type="pin"][data-element-id="${pinState.id}"]`,
      );

      if (pinState.visibility === "hide") {
        if (el) el.style.display = "none";
      } else if (pinState.visibility === "disable") {
        if (el) {
          el.style.display = "";
          el.style.opacity = "0.3";
          el.style.pointerEvents = "none";
        }
      } else {
        if (el) {
          el.style.display = "";
          el.style.opacity = "1";
          el.style.pointerEvents = "auto";
        }
      }
    }
  },

  updateDisplayZones() {
    const displayValues = this.el.querySelectorAll(".zone-display-value[data-ref]");
    for (const el of displayValues) {
      const ref = el.dataset.ref;
      el.textContent = this.variables[ref] ?? "—";
    }
  },
};
