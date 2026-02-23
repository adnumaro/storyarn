/**
 * StoryarnMagneticConnection - Lit component for rendering the magnetic
 * connection indicator (the "snap preview" shown when dragging near a socket).
 *
 * Based on Rete.js MagneticConnection (MIT License).
 * Adapted from React/styled-components to Lit for Storyarn.
 */

import { css, html, LitElement } from "lit";

export class StoryarnMagneticConnection extends LitElement {
  static get properties() {
    return {
      path: { type: String },
    };
  }

  static styles = css`
    :host {
      display: contents;
    }

    svg {
      overflow: visible !important;
      position: absolute;
      pointer-events: none;
      width: 9999px;
      height: 9999px;
    }

    path {
      fill: none;
      stroke-width: 2px;
      stroke: color-mix(in oklch, var(--color-base-content, #a6adbb) 25%, transparent);
      pointer-events: none;
      stroke-dasharray: 6 4;
    }
  `;

  render() {
    if (!this.path) return html``;

    return html`
      <svg data-testid="magnetic-connection">
        <path d="${this.path}"></path>
      </svg>
    `;
  }
}

customElements.define("storyarn-magnetic-connection", StoryarnMagneticConnection);
