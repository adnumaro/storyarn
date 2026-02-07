/**
 * Dialogue node type definition.
 */
import { html } from "lit";
import { MessageSquare } from "lucide";
import { createIconSvg } from "../node_config.js";
import {
  nodeShell,
  defaultHeader,
  speakerHeader,
  renderPreview,
  renderSockets,
} from "./render_helpers.js";

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
    const { node, nodeData, config, selected, emit, pagesMap } = ctx;
    const color = this.nodeColor(nodeData, config, pagesMap);
    const indicators = this.getIndicators(nodeData);
    const preview = this.getPreviewText(nodeData);

    const speakerId = nodeData.speaker_page_id;
    const speakerPage = speakerId ? pagesMap?.[String(speakerId)] : null;

    const headerHtml = speakerPage
      ? speakerHeader(config, color, speakerPage, indicators)
      : defaultHeader(config, color, indicators);

    return nodeShell(color, selected, html`
      ${headerHtml}
      ${nodeData.stage_directions
        ? html`<div class="stage-directions">${nodeData.stage_directions}</div>`
        : ""}
      ${renderPreview(preview)}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
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
    if (data.input_condition)
      indicators.push({ text: "🔒", title: "Has input condition", class: "input-condition" });
    if (data.output_instruction)
      indicators.push({
        text: "⚡",
        title: "Has output instruction",
        class: "output-instruction",
      });
    if (data.audio_asset_id) indicators.push({ type: "audio", title: "Has audio" });
    return indicators;
  },

  formatOutputLabel(key, data) {
    const response = data.responses?.find((r) => r.id === key);
    return response?.text || "";
  },

  getOutputBadges(key, data) {
    const badges = [];
    const response = data.responses?.find((r) => r.id === key);
    if (!response?.text) {
      badges.push({ type: "error", title: "Empty response text" });
    }
    if (response?.condition) {
      badges.push({ text: "?", class: "condition-badge", title: "Has condition" });
    }
    return badges;
  },

  nodeColor(data, config, pagesMap) {
    const speakerId = data.speaker_page_id;
    const speakerPage = speakerId ? pagesMap?.[String(speakerId)] : null;
    return speakerPage?.color || config.color;
  },

  needsRebuild(oldData, newData) {
    return JSON.stringify(oldData) !== JSON.stringify(newData);
  },
};
