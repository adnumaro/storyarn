/**
 * Shared rendering primitives for per-type node render() methods.
 * Pure functions returning Lit html templates — no class, no state.
 *
 * Uses Tailwind classes (available via adoptedStyleSheets) for layout/typography.
 * CSS-in-JS styles (storyarn_node_styles.js) handle shadows, animations, pseudo-elements.
 */

import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { TriangleAlert, Volume2 } from "lucide";
import { createIconHTML } from "../node_config.js";

// Pre-create icon SVGs (shared across all node types)
const AUDIO_ICON = createIconHTML(Volume2, { size: 12 });
const ALERT_ICON = createIconHTML(TriangleAlert);

/** Header style: solid color + right-shifted gradient highlight */
export function headerStyle(color) {
  return `background: linear-gradient(to right, ${color} 40%, color-mix(in oklch, ${color} 85%, white) 100%)`;
}

/**
 * Outer node wrapper with border color and selection state.
 */
export function nodeShell(nodeColor, selected, content, extraClass = "") {
  const borderColor = `${nodeColor}40`;
  return html`
    <div
      class="node relative bg-base-200 rounded-xl min-w-[180px] border-[1.5px] ${selected ? "selected" : ""} ${extraClass}"
      style="--node-border-color: ${borderColor}; --node-color: ${nodeColor}; border-color: var(--node-border-color, transparent)"
    >
      ${content}
    </div>
  `;
}

/**
 * Default header with icon + label.
 */
export function defaultHeader(config, nodeColor, indicators) {
  return html`
    <div class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]" style="${headerStyle(nodeColor)}">
      <span class="flex items-center">${unsafeSVG(config.icon)}</span>
      <span>${config.label}</span>
      ${renderIndicators(indicators)}
    </div>
  `;
}

/**
 * Speaker header with avatar (or icon fallback) + name.
 */
export function speakerHeader(config, nodeColor, speakerSheet, indicators) {
  return html`
    <div class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]" style="${headerStyle(nodeColor)}">
      ${
        speakerSheet.avatar_url
          ? html`<img src="${speakerSheet.avatar_url}" class="size-8 rounded-full object-cover shrink-0" alt="" />`
          : html`<span class="flex items-center">${unsafeSVG(config.icon)}</span>`
      }
      <span class="overflow-hidden text-ellipsis whitespace-nowrap">${speakerSheet.name}</span>
      ${renderIndicators(indicators)}
    </div>
  `;
}

/**
 * Renders indicator badges in the header.
 */
export function renderIndicators(indicators) {
  if (!indicators || indicators.length === 0) return "";
  return html`
    <span class="flex items-center gap-1 ml-auto">
      ${indicators.map((ind) => {
        if (ind.type === "audio")
          return html`<span class="inline-flex items-center justify-center ml-auto opacity-80" title="${ind.title}"
            >${unsafeSVG(AUDIO_ICON)}</span
          >`;
        if (ind.type === "error")
          return html`<span class="error-badge inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full mr-0.5 cursor-help" title="${ind.title}"
            >${unsafeSVG(ALERT_ICON)}</span
          >`;
        if (ind.svg)
          return html`<span class="inline-flex items-center justify-center text-[10px] opacity-90 ${ind.class || ""}" title="${ind.title}"
            >${unsafeSVG(ind.svg)}</span
          >`;
        return html`<span
          class="inline-flex items-center justify-center text-[10px] opacity-90 ${ind.class || ""}"
          title="${ind.title}"
          >${ind.text}</span
        >`;
      })}
    </span>
  `;
}

/**
 * Renders preview text block.
 */
export function renderPreview(text) {
  if (!text) return "";
  return html`<div class="text-[11px] text-base-content/80 px-3 py-2 max-w-[200px] border-b border-base-content/10 break-words"><div class="line-clamp-4 leading-[1.4]">${text}</div></div>`;
}

/**
 * Renders a clickable navigation link block (used by hub/jump).
 */
export function renderNavLink(text, event, detailKey, nodeId, _emit) {
  return html`<div class="text-[11px] text-base-content/80 px-3 py-2 max-w-[200px] border-b border-base-content/10 break-words">
    <div
      class="line-clamp-4 leading-[1.4] nav-link cursor-pointer underline decoration-dotted underline-offset-2"
      @pointerdown=${(e) => {
        e.stopPropagation();
        e.target.dispatchEvent(
          new CustomEvent(event, {
            bubbles: true,
            composed: true,
            detail: { [detailKey]: nodeId },
          }),
        );
      }}
    >
      ${text}
    </div>
  </div>`;
}

/**
 * Renders sockets (inputs + outputs) for a node.
 * Handles the single-row optimisation (1 input + 1 output) and the multi-row layout.
 *
 * @param {object}   node     - Full node data (has .inputs, .outputs, .id)
 * @param {object}   nodeData - The node's domain data
 * @param {object}   def      - Per-type definition (for config.dynamicOutputs, formatOutputLabel, getOutputBadges)
 * @param {Function} emit     - Rete emit function
 */
export function renderSockets(node, nodeData, def, emit) {
  const inputs = Object.entries(node.inputs || {});
  const outputs = Object.entries(node.outputs || {});
  if (inputs.length === 1 && outputs.length === 1 && !def?.config?.dynamicOutputs) {
    const [inputKey, input] = inputs[0];
    const [outputKey, output] = outputs[0];

    return html`
      <div class="sockets-row flex justify-between items-center py-1">
        <rete-ref
          class="input-socket"
          .data=${{
            type: "socket",
            side: "input",
            key: inputKey,
            nodeId: node.id,
            payload: input.socket,
          }}
          .emit=${emit}
        ></rete-ref>
        <span class="text-[11px] text-base-content/70 ml-1">${inputKey}</span>
        <span class="text-[11px] text-base-content/70 ml-auto mr-1">${outputKey}</span>
        <rete-ref
          class="output-socket"
          .data=${{
            type: "socket",
            side: "output",
            key: outputKey,
            nodeId: node.id,
            payload: output.socket,
          }}
          .emit=${emit}
        ></rete-ref>
      </div>
    `;
  }

  return html`
    ${inputs.map(
      ([key, input]) => html`
        <div class="flex items-center py-1 text-[11px] text-base-content/70 justify-start">
          <rete-ref
            class="input-socket"
            .data=${{
              type: "socket",
              side: "input",
              key,
              nodeId: node.id,
              payload: input.socket,
            }}
            .emit=${emit}
          ></rete-ref>
        </div>
      `,
    )}
    ${outputs.map(([key, output]) => {
      const outputLabel = def?.formatOutputLabel?.(key, nodeData) ?? key;
      const badges = def?.getOutputBadges?.(key, nodeData) || [];
      const labelTitle = typeof outputLabel === "string" ? outputLabel : key;

      return html`
        <div class="flex items-center py-1 text-[11px] text-base-content/70 justify-end">
          ${badges.map((badge) => {
            if (badge.type === "error")
              return html`<div class="error-badge inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full mr-0.5 cursor-help" title="${badge.title}">${unsafeSVG(ALERT_ICON)}</div>`;
            if (badge.type === "indicator")
              return html`<span class="response-indicator tooltip tooltip-top" style="background:${badge.color}" data-tip="${badge.title}"></span>`;
            return html`<span class="${badge.class}" title="${badge.title}">${badge.text}</span>`;
          })}
          <span class="px-2 max-w-[220px] break-words text-right" title="${labelTitle}">${outputLabel}</span>
          <rete-ref
            class="output-socket"
            .data=${{
              type: "socket",
              side: "output",
              key,
              nodeId: node.id,
              payload: output.socket,
            }}
            .emit=${emit}
          ></rete-ref>
        </div>
      `;
    })}
  `;
}
