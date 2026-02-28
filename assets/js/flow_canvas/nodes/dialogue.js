/**
 * Dialogue node type definition.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { MessageSquare } from "lucide";
import { createIconSvg } from "../node_config.js";
import { headerStyle, nodeShell, renderIndicators, renderSockets } from "./render_helpers.js";

export default {
  config: {
    label: "Dialogue",
    color: "#3b82f6",
    icon: createIconSvg(MessageSquare),
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit, sheetsMap } = ctx;
    const color = this.nodeColor(nodeData, config, sheetsMap);
    const indicators = this.getIndicators(nodeData);
    const preview = this.getPreviewText(nodeData);

    const speakerId = nodeData.speaker_sheet_id;
    const speakerSheet = speakerId ? sheetsMap?.[String(speakerId)] : null;

    // Header: always icon + speaker name (or "Dialogue")
    const headerLabel = speakerSheet?.name || config.label;
    const headerHtml = html`
      <div class="header" style="${headerStyle(color)}">
        <span class="icon">${unsafeSVG(config.icon)}</span>
        <span class="speaker-name">${headerLabel}</span>
        ${renderIndicators(indicators)}
      </div>
    `;

    // Visual strip: banner > avatar+color > color only
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
