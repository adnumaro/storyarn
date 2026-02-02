/**
 * StoryarnConnection - Custom LitElement component for rendering connections between nodes.
 */

import { LitElement, css, html } from "lit";

export class StoryarnConnection extends LitElement {
  static get properties() {
    return {
      path: { type: String },
      start: { type: Object },
      end: { type: Object },
      data: { type: Object },
      selected: { type: Boolean },
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

    path {
      fill: none;
      stroke: oklch(var(--bc, 0.7 0 0) / 0.4);
      stroke-width: 2px;
      pointer-events: auto;
      transition: stroke 0.15s ease, stroke-width 0.15s ease;
      cursor: pointer;
    }

    path:hover,
    path.selected {
      stroke: oklch(var(--p, 0.6 0.2 250));
      stroke-width: 3px;
    }

    .label-group {
      pointer-events: auto;
      cursor: pointer;
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
    const midpoint = label ? this.getMidpoint() : null;
    const labelWidth = label ? Math.min(label.length * 6 + 10, 80) : 0;

    return html`
      <svg data-testid="connection">
        <path
          d="${this.path}"
          class="${this.selected ? "selected" : ""}"
          @dblclick=${this.handleDoubleClick}
        ></path>
        ${
          midpoint && label
            ? html`
              <g
                class="label-group"
                transform="translate(${midpoint.x}, ${midpoint.y})"
                @dblclick=${this.handleDoubleClick}
              >
                <rect
                  class="label-bg"
                  x="${-labelWidth / 2}"
                  y="-9"
                  width="${labelWidth}"
                  height="18"
                ></rect>
                <text class="label-text">${label}</text>
              </g>
            `
            : ""
        }
      </svg>
    `;
  }

  handleDoubleClick(e) {
    e.stopPropagation();
    if (this.data?.id) {
      this.dispatchEvent(
        new CustomEvent("connection-dblclick", {
          detail: { connectionId: this.data.id },
          bubbles: true,
          composed: true,
        }),
      );
    }
  }
}

customElements.define("storyarn-connection", StoryarnConnection);
