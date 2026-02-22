/**
 * Interaction node type definition.
 *
 * References a map in the project. Event zones on that map become dynamic
 * output pins. The Story Player pauses at this node, renders the map, and
 * advances through the pin corresponding to the event zone the player clicks.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ExternalLink, Gamepad2 } from "lucide";
import { createIconHTML, createIconSvg } from "../node_config.js";
import {
  defaultHeader,
  nodeShell,
  renderNavLink,
  renderPreview,
  renderSockets,
} from "./render_helpers.js";

const NAV_ICON = createIconHTML(ExternalLink, { size: 12 });

export default {
  config: {
    label: "Interaction",
    color: "#f59e0b",
    icon: createIconSvg(Gamepad2),
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },

  /**
   * Dynamic outputs: one per event zone on the referenced map.
   */
  createOutputs(data) {
    const events = data.event_zone_names;
    if (events && events.length > 0) return events;
    return null; // Fall back to static ["output"]
  },

  /** Returns the display label for an output pin (event zone label or key fallback). */
  formatOutputLabel(key, data) {
    const labels = data.event_zone_labels || {};
    return labels[key] || key;
  },

  /** Returns visual badges for an output pin (none for interaction). */
  getOutputBadges(_key, _data) {
    return [];
  },

  /** Renders the interaction node with map nav link and event zone sockets. */
  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const preview = this.getPreviewText(nodeData);

    let navContent = null;
    if (nodeData.map_name) {
      navContent = html`<span style="display:inline-flex;align-items:center;gap:4px">${unsafeSVG(NAV_ICON)} ${nodeData.map_name}</span>`;
    }

    return nodeShell(
      config.color,
      selected,
      html`
      ${defaultHeader(config, config.color, this.getIndicators(nodeData))}
      ${
        navContent
          ? renderNavLink(navContent, "navigate-to-interaction-map", "mapId", nodeData.map_id, emit)
          : ""
      }
      ${!nodeData.map_id ? renderPreview(preview) : ""}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `,
    );
  },

  /** Returns warning indicators (e.g., "No map selected"). */
  getIndicators(data) {
    const indicators = [];
    if (!data.map_id) {
      indicators.push({ type: "error", title: "No map selected" });
    }
    return indicators;
  },

  /** Returns the preview text shown inside the node body. */
  getPreviewText(data) {
    if (data.map_name) return data.map_name;
    if (data.map_id) return `Map #${data.map_id}`;
    return "No map selected";
  },

  /** Returns true if the node structure changed (map or event zones). */
  needsRebuild(oldData, newData) {
    if (oldData?.map_id !== newData.map_id) return true;
    if (JSON.stringify(oldData?.event_zone_names) !== JSON.stringify(newData.event_zone_names))
      return true;
    return false;
  },
};
