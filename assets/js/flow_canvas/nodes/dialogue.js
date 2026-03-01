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
      <div class="header" style="${headerStyle(color)}">
        <span class="icon">${unsafeSVG(config.icon)}</span>
        <span class="speaker-name">${headerLabel}</span>
        ${renderIndicators(indicators)}
      </div>
    `;

    const bannerUrl = speakerSheet?.banner_url;
    const avatarUrl = speakerSheet?.avatar_url;

    const visualHtml = bannerUrl
      ? html`<img src="${bannerUrl}" class="dialogue-banner" alt="" />`
      : avatarUrl
        ? html`<div
            class="dialogue-visual"
            style="background-color: ${color}20"
          >
            <img src="${avatarUrl}" class="dialogue-avatar" alt="" />
          </div>`
        : speakerSheet
          ? html`<div
              class="dialogue-visual"
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
          <div class="dialogue-content">
            ${
              nodeData.stage_directions
                ? html`<div class="stage-directions-inline">
                  ${nodeData.stage_directions}
                </div>`
                : ""
            }
            ${preview ? html`<div class="dialogue-text">${preview}</div>` : ""}
          </div>
        `
      : "";

    return nodeShell(
      color,
      selected,
      html`
        ${headerHtml} ${visualHtml} ${bodyHtml}
        <div class="content compact">
          ${renderSockets(node, nodeData, this, emit)}
        </div>
      `,
      "dialogue",
    );
  },

  renderEdit(ctx) {
    const { node, nodeData, config, selected, emit, sheetsMap, onSave } = ctx;
    const { color, visualHtml } = this._renderChrome(nodeData, config, sheetsMap);
    const speakerId = nodeData.speaker_sheet_id;
    const speakerSheet = speakerId ? sheetsMap?.[String(speakerId)] : null;
    const speakerLabel = speakerSheet?.name || config.label;

    const editHeaderHtml = html`
      <div class="header" style="${headerStyle(color)}">
        <span class="icon">${unsafeSVG(config.icon)}</span>
        <button
          class="inline-speaker-trigger"
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
          <span class="inline-speaker-label">${speakerLabel}</span>
          ${unsafeSVG(CHEVRON_ICON)}
        </button>
      </div>
    `;
    const plainText = this.getPreviewText(nodeData);
    const stopDrag = (e) => e.stopPropagation();

    const bodyHtml = html`
      <div class="dialogue-content">
        <input
          class="inline-input"
          placeholder="Stage directions…"
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
          class="inline-textarea"
          placeholder="Dialogue text…"
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

    return nodeShell(
      color,
      selected,
      html`
        ${editHeaderHtml} ${visualHtml} ${bodyHtml}
        <div class="content compact">
          ${renderSockets(node, nodeData, this, emit)}
        </div>
      `,
      "dialogue",
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
    const textContent = data.text
      ? new DOMParser().parseFromString(data.text, "text/html").body.textContent
      : "";
    return textContent || "";
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
    if (response.condition) {
      badges.push({ text: "?", class: "condition-badge", title: "Has condition" });
    }
    return badges;
  },

  nodeColor(data, config, sheetsMap) {
    const speakerId = data.speaker_sheet_id;
    const speakerSheet = speakerId ? sheetsMap?.[String(speakerId)] : null;
    return speakerSheet?.color || config.color;
  },

  needsRebuild(oldData, newData) {
    return JSON.stringify(oldData) !== JSON.stringify(newData);
  },
};
