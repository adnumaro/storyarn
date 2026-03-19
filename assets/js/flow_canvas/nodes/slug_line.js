/**
 * Slug Line node type definition.
 *
 * A pass-through node that establishes location and time context.
 * Displays a screenplay slug line (e.g., "INT. LOBBY - NIGHT")
 * and references a location sheet for color and avatar.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { Clapperboard } from "lucide";
import { createIconSvg } from "../node_config.js";
import {
  headerStyle,
  nodeShell,
  renderIndicators,
  renderPreview,
  renderSockets,
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
    const avatarId = nodeData.avatar_id;
    const avatars = locSheet?.avatars || [];
    const overrideAvatar = avatarId ? avatars.find((a) => a.id === avatarId) : null;
    const overrideUrl = overrideAvatar?.url;

    // Header always shows the clapperboard icon + location name
    const headerLabel = locSheet?.name || config.label;
    const headerHtml = html`
      <div class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]" style="${headerStyle(color)}">
        <span class="flex items-center">${unsafeSVG(config.icon)}</span>
        <span class="overflow-hidden text-ellipsis whitespace-nowrap">${headerLabel}</span>
        ${renderIndicators(indicators)}
      </div>
    `;

    // Visual strip: override → banner → avatar → empty (same pattern as dialogue)
    const bannerUrl = locSheet?.banner_url;
    const avatarUrl = locSheet?.avatar_url;

    const visualHtml = overrideUrl
      ? html`<img src="${overrideUrl}" class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3" alt="" />`
      : bannerUrl
        ? html`<img src="${bannerUrl}" class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3" alt="" />`
        : avatarUrl
          ? html`<div
              class="flex items-center justify-center px-3 pt-3"
              style="background-color: ${color}20"
            >
              <img src="${avatarUrl}" class="size-16 rounded-lg object-cover shadow-md" alt="" />
            </div>`
          : "";

    const hasContent = slugLine || description || visualHtml !== "";
    const extraClass = hasContent ? "slug-line min-w-[200px] max-w-[280px]" : "";

    return nodeShell(
      color,
      selected,
      html`
        ${headerHtml} ${visualHtml}
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
      extraClass,
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
    if (oldData?.avatar_id !== newData.avatar_id) return true;
    if (oldData?.int_ext !== newData.int_ext) return true;
    if (oldData?.sub_location !== newData.sub_location) return true;
    if (oldData?.time_of_day !== newData.time_of_day) return true;
    if (oldData?.description !== newData.description) return true;
    return false;
  },
};
