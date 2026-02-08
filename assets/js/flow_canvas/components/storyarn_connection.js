/**
 * StoryarnConnection - Custom LitElement component for rendering connections between nodes.
 *
 * Note: Condition rendering was removed based on research findings.
 * See docs/research/DIALOGUE_CONDITIONS_RESEARCH.md for details.
 */

import { LitElement, css, html } from "lit";

export class StoryarnConnection extends LitElement {
  static get properties() {
    return {
      path: { type: String },
      start: { type: Object },
      end: { type: Object },
      data: { type: Object },
    };
  }

  static styles = css`
    :host {
      display: contents;
    }

    svg {
      overflow: visible;
      position: absolute;
      pointer-events: none;
      width: 9999px;
      height: 9999px;
    }

    /* Invisible hit area for hover detection */
    path.hit-area {
      fill: none;
      stroke: transparent;
      stroke-width: 20px;
      pointer-events: auto;
    }

    /* Visible connection line — uses CSS custom properties for debug overrides */
    path.visible {
      fill: none;
      stroke: var(--conn-stroke, oklch(var(--bc, 0.7 0 0) / 0.4));
      stroke-width: var(--conn-stroke-width, 2px);
      stroke-dasharray: var(--conn-dash, none);
      animation: var(--conn-animation, none);
      pointer-events: none;
      transition: stroke 0.15s ease, stroke-width 0.15s ease;
    }

    /* Hover state */
    path.hit-area:hover + path.visible {
      stroke: oklch(var(--p, 0.6 0.2 250));
      stroke-width: 3px;
    }

    @keyframes debug-flow {
      to {
        stroke-dashoffset: -12;
      }
    }

    .label-group {
      pointer-events: none;
    }

    .label-bg {
      fill: oklch(var(--b1, 0.2 0 0));
      stroke: oklch(var(--bc, 0.7 0 0) / 0.3);
      stroke-width: 1px;
      rx: 3;
      ry: 3;
    }

    .label-text {
      fill: oklch(var(--bc, 0.8 0 0));
      font-size: 10px;
      font-family: system-ui, sans-serif;
      dominant-baseline: middle;
      text-anchor: middle;
    }
  `;

  /**
   * Calculate midpoint of bezier curve path for label positioning.
   * @returns {{x: number, y: number}|null}
   */
  getMidpoint() {
    if (!this.path) return null;

    // Parse the path to get control points
    // Path format: M startX,startY C cp1X,cp1Y cp2X,cp2Y endX,endY
    const pathMatch = this.path.match(
      /M\s*([\d.-]+)[,\s]*([\d.-]+)\s*C\s*([\d.-]+)[,\s]*([\d.-]+)\s*([\d.-]+)[,\s]*([\d.-]+)\s*([\d.-]+)[,\s]*([\d.-]+)/,
    );

    if (!pathMatch) return null;

    const [, x0, y0, x1, y1, x2, y2, x3, y3] = pathMatch.map(Number);

    // Calculate midpoint of cubic bezier at t=0.5
    const t = 0.5;
    const mt = 1 - t;
    const mx = mt ** 3 * x0 + 3 * mt ** 2 * t * x1 + 3 * mt * t ** 2 * x2 + t ** 3 * x3;
    const my = mt ** 3 * y0 + 3 * mt ** 2 * t * y1 + 3 * mt * t ** 2 * y2 + t ** 3 * y3;

    return { x: mx, y: my };
  }

  render() {
    const label = this.data?.label;

    // Get midpoint for label positioning
    const midpoint = label ? this.getMidpoint() : null;

    // Calculate label dimensions
    const labelWidth = label ? Math.min(label.length * 6 + 10, 80) : 0;

    return html`
      <svg data-testid="connection">
        <!-- Invisible wider hit area for hover detection -->
        <path d="${this.path}" class="hit-area"></path>
        <!-- Visible connection line -->
        <path d="${this.path}" class="visible"></path>
        ${
          midpoint && label
            ? html`
              <g class="label-group" transform="translate(${midpoint.x}, ${midpoint.y})">
                <rect class="label-bg" x="${-labelWidth / 2}" y="-9" width="${labelWidth}" height="18"></rect>
                <text class="label-text">${label}</text>
              </g>
            `
            : ""
        }
      </svg>
    `;
  }
}

customElements.define("storyarn-connection", StoryarnConnection);
