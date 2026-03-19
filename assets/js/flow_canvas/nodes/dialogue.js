/**
 * Dialogue node type definition.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ChevronDown, MessageSquare } from "lucide";
import { createIconHTML, createIconSvg } from "../node_config.js";
import { headerStyle, nodeShell, renderIndicators, renderSockets } from "./render_helpers.js";

const CHEVRON_ICON = createIconHTML(ChevronDown, { size: 14 });

export default {
  config: {
    label: "Dialogue",
    color: "#3b82f6",
    icon: createIconSvg(MessageSquare),
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },

  /** Shared header + visual strip for both render modes. */
  _renderChrome(nodeData, config, sheetsMap) {
    const color = this.nodeColor(nodeData, config, sheetsMap);
    const indicators = this.getIndicators(nodeData);
    const speakerId = nodeData.speaker_sheet_id;
    const speakerSheet = speakerId ? sheetsMap?.[String(speakerId)] : null;

    const headerLabel = speakerSheet?.name || config.label;
    const headerHtml = html`
      <div class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]" style="${headerStyle(color)}">
        <span class="flex items-center">${unsafeSVG(config.icon)}</span>
        <span class="overflow-hidden text-ellipsis whitespace-nowrap">${headerLabel}</span>
        ${renderIndicators(indicators)}
      </div>
    `;

    // Resolve avatar: specific avatar_id override > default avatar > banner > fallback
    const avatarId = nodeData.avatar_id;
    const avatars = speakerSheet?.avatars || [];
    const overrideAvatar = avatarId ? avatars.find((a) => a.id === avatarId) : null;
    const overrideUrl = overrideAvatar?.url;
    const bannerUrl = speakerSheet?.banner_url;
    const avatarUrl = speakerSheet?.avatar_url;

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
          : speakerSheet
            ? html`<div
                class="flex items-center justify-center px-3 pt-3"
                style="background-color: ${color}20"
              ></div>`
            : "";

    return { color, headerHtml, visualHtml };
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit, sheetsMap } = ctx;
    const { color, headerHtml, visualHtml } = this._renderChrome(nodeData, config, sheetsMap);
    const preview = this.getPreviewText(nodeData);

    // Body: stage directions + preview text (stacked rows)
    const hasText = nodeData.stage_directions || preview;

    const bodyHtml = hasText
      ? html`
          <div class="px-3.5 pt-2.5 pb-3">
            ${
              nodeData.stage_directions
                ? html`<div class="italic text-base-content/55 text-xs mb-1 break-words">
                  ${nodeData.stage_directions}
                </div>`
                : ""
            }
            ${preview ? html`<div class="text-sm text-base-content/85 leading-relaxed break-words whitespace-pre-wrap">${preview}</div>` : ""}
          </div>
        `
      : "";

    const hasContent = hasText || visualHtml !== "" || nodeData.responses?.length > 0;
    const extraClass = hasContent ? "dialogue min-w-[280px] max-w-[350px]" : "dialogue";

    return nodeShell(
      color,
      selected,
      html`
        ${headerHtml} ${visualHtml} ${bodyHtml}
        <div class="py-1.5 border-t border-base-content/10">
          ${renderSockets(node, nodeData, this, emit)}
        </div>
      `,
      extraClass,
    );
  },

  renderEdit(ctx) {
    const { node, nodeData, config, selected, emit, sheetsMap, labels, onSave } = ctx;
    const { color, visualHtml } = this._renderChrome(nodeData, config, sheetsMap);
    const speakerId = nodeData.speaker_sheet_id;
    const speakerSheet = speakerId ? sheetsMap?.[String(speakerId)] : null;
    const speakerLabel = speakerSheet?.name || config.label;

    const editHeaderHtml = html`
      <div class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]" style="${headerStyle(color)}">
        <span class="flex items-center">${unsafeSVG(config.icon)}</span>
        <button
          class="inline-speaker-trigger flex-1 min-w-0 flex items-center gap-1 bg-transparent border-none text-white font-medium text-[13px] cursor-pointer p-0 outline-none font-[inherit]"
          @pointerdown=${(e) => e.stopPropagation()}
          @keydown=${(e) => e.stopPropagation()}
          @click=${(e) => {
            e.stopPropagation();
            const host = e.currentTarget.getRootNode().host;
            host?.dispatchEvent(
              new CustomEvent("speaker-select-open", {
                bubbles: true,
                composed: true,
                detail: { trigger: e.currentTarget },
              }),
            );
          }}
        >
          <span class="overflow-hidden text-ellipsis whitespace-nowrap">${speakerLabel}</span>
          ${unsafeSVG(CHEVRON_ICON)}
        </button>
      </div>
    `;
    const plainText = this.getPreviewText(nodeData);
    const stopDrag = (e) => e.stopPropagation();

    const bodyHtml = html`
      <div class="px-3.5 pt-2.5 pb-3">
        <input
          class="inline-input w-full bg-transparent border-0 border-b italic text-xs py-0.5 mb-1 outline-none font-[inherit]"
          placeholder=${labels?.stage_directions || "Stage directions…"}
          .value=${nodeData.stage_directions || ""}
          @pointerdown=${stopDrag}
          @blur=${(e) => {
            const val = e.target.value.trim();
            if (val !== (nodeData.stage_directions || "")) {
              onSave("stage_directions", val);
            }
          }}
          @keydown=${(e) => {
            if (e.key === "Enter") e.target.blur();
            e.stopPropagation();
          }}
        />
        <textarea
          class="inline-textarea w-full bg-transparent border-0 text-sm p-0 resize-none outline-none leading-relaxed overflow-hidden font-[inherit]"
          placeholder=${labels?.dialogue_text || "Dialogue text…"}
          .value=${plainText}
          @pointerdown=${stopDrag}
          @input=${(e) => {
            e.target.style.height = "auto";
            e.target.style.height = `${e.target.scrollHeight}px`;
          }}
          @blur=${(e) => {
            const val = e.target.value.trim();
            if (val !== plainText) {
              onSave("text", val);
            }
          }}
          @keydown=${(e) => {
            if (e.key === "Escape") e.target.blur();
            e.stopPropagation();
          }}
        ></textarea>
      </div>
    `;

    // Edit mode always shows inputs, so it always has content
    return nodeShell(
      color,
      selected,
      html`
        ${editHeaderHtml} ${visualHtml} ${bodyHtml}
        <div class="py-1.5 border-t border-base-content/10">
          ${renderSockets(node, nodeData, this, emit)}
        </div>
      `,
      "dialogue min-w-[280px] max-w-[350px]",
    );
  },

  /**
   * Creates dynamic outputs based on responses.
   */
  createOutputs(data) {
    if (data.responses?.length > 0) {
      return data.responses.map((r) => r.id);
    }
    return null;
  },

  getPreviewText(data) {
    if (!data.text) return "";
    // Add newline after block-level closing tags so textContent preserves paragraph breaks
    const spaced = data.text.replace(/<\/(p|div|h[1-6])>/gi, "</$1>\n");
    const textContent = new DOMParser().parseFromString(spaced, "text/html").body.textContent || "";
    return textContent.replace(/\n{3,}/g, "\n\n").trim();
  },

  getIndicators(data) {
    const indicators = [];
    if (data.audio_asset_id) indicators.push({ type: "audio", title: "Has audio" });
    return indicators;
  },

  formatOutputLabel(key, data) {
    const response = data.responses?.find((r) => r.id === key);
    return response?.text || "";
  },

  getOutputBadges(key, data) {
    const response = data.responses?.find((r) => r.id === key);
    if (!response) return [];
    const badges = [];
    if (!response.text) {
      badges.push({ type: "error", title: "Empty response text" });
    }
    if (response.has_type_warnings) {
      badges.push({ type: "error", title: "Type mismatch in assignments" });
    }
    if (response.condition) {
      badges.push({ type: "indicator", color: "#eab308", title: "Has condition" });
    }
    const assignments = response.instruction_assignments || [];
    if (assignments.length > 0) {
      badges.push({ type: "indicator", color: "#ec4899", title: "Has instructions" });
    }
    return badges;
  },

  nodeColor(data, config, sheetsMap) {
    const speakerId = data.speaker_sheet_id;
    const speakerSheet = speakerId ? sheetsMap?.[String(speakerId)] : null;
    return speakerSheet?.color || config.color;
  },

  needsRebuild(oldData, newData) {
    // Only rebuild for structural changes that affect pins or visual chrome.
    // Text/stage_directions are content-only — skip to avoid exiting inline edit mode.
    if (oldData?.speaker_sheet_id !== newData.speaker_sheet_id) return true;
    if (oldData?.audio_asset_id !== newData.audio_asset_id) return true;
    if (oldData?.avatar_id !== newData.avatar_id) return true;
    if (oldData?.has_stale_refs !== newData.has_stale_refs) return true;

    const oldResp = oldData?.responses || [];
    const newResp = newData.responses || [];
    if (oldResp.length !== newResp.length) return true;
    for (let i = 0; i < oldResp.length; i++) {
      if (oldResp[i].id !== newResp[i].id) return true;
      if (oldResp[i].has_type_warnings !== newResp[i].has_type_warnings) return true;
      if (Boolean(oldResp[i].condition) !== Boolean(newResp[i].condition)) return true;
      const oldAssign = oldResp[i].instruction_assignments?.length || 0;
      const newAssign = newResp[i].instruction_assignments?.length || 0;
      if (oldAssign > 0 !== newAssign > 0) return true;
    }

    return false;
  },
};
