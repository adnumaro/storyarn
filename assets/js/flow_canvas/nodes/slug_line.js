/**
 * Slug Line node type definition.
 *
 * A pass-through node that establishes location and time context.
 * Displays a screenplay slug line (e.g., "INT. LOBBY - NIGHT")
 * and references a location sheet for color and avatar.
 */
import { html } from "lit";
import { Clapperboard } from "lucide";
import { createIconSvg } from "../node_config.js";
import {
  defaultHeader,
  nodeShell,
  renderPreview,
  renderSockets,
  speakerHeader,
} from "./render_helpers.js";

export default {
  config: {
    label: "Slug Line",
    color: "#06b6d4",
    icon: createIconSvg(Clapperboard),
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: false,
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit, sheetsMap } = ctx;
    const color = this.nodeColor(nodeData, config, sheetsMap);
    const indicators = this.getIndicators(nodeData);
    const slugLine = this.getSlugLine(nodeData);
    const description = nodeData.description || "";

    const locId = nodeData.location_sheet_id;
    const locSheet = locId ? sheetsMap?.[String(locId)] : null;

    const headerHtml = locSheet
      ? speakerHeader(config, color, locSheet, indicators)
      : defaultHeader(config, color, indicators);

    return nodeShell(
      color,
      selected,
      html`
        ${headerHtml}
        ${
          slugLine
            ? html`<div class="text-[11px] text-base-content/80 px-3 py-2 max-w-[200px] border-b border-base-content/10 break-words">
              <div class="line-clamp-4 leading-[1.4] font-bold text-xs tracking-wide">
                ${slugLine}
              </div>
            </div>`
            : ""
        }
        ${renderPreview(description)}
        <div class="py-1">${renderSockets(node, nodeData, this, emit)}</div>
      `,
    );
  },

  getSlugLine(data) {
    const parts = [];
    const intExt = (data.int_ext || "").toUpperCase().replace("_", "./");
    if (intExt) parts.push(`${intExt}.`);
    if (data.sub_location) parts.push(data.sub_location.toUpperCase());
    if (data.time_of_day) {
      if (parts.length > 0) parts.push("-");
      parts.push(data.time_of_day.toUpperCase());
    }
    return parts.join(" ");
  },

  getPreviewText(data) {
    return data.description || "";
  },

  getIndicators(data) {
    const indicators = [];
    if (!data.location_sheet_id) {
      indicators.push({ type: "error", title: "No location set" });
    }
    return indicators;
  },

  nodeColor(data, config, sheetsMap) {
    const locId = data.location_sheet_id;
    const locSheet = locId ? sheetsMap?.[String(locId)] : null;
    return locSheet?.color || config.color;
  },

  needsRebuild(oldData, newData) {
    if (oldData?.location_sheet_id !== newData.location_sheet_id) return true;
    if (oldData?.int_ext !== newData.int_ext) return true;
    if (oldData?.sub_location !== newData.sub_location) return true;
    if (oldData?.time_of_day !== newData.time_of_day) return true;
    if (oldData?.description !== newData.description) return true;
    return false;
  },
};
