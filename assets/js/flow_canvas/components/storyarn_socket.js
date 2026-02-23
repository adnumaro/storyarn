/**
 * StoryarnSocket - Custom LitElement component for rendering node sockets.
 */

import { css, html, LitElement } from "lit";

export class StoryarnSocket extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
    };
  }

  static styles = css`
    :host {
      display: inline-block;
    }

    .socket {
      width: 10px;
      height: 10px;
      background: color-mix(in oklch, var(--color-base-content, #a6adbb) 25%, transparent);
      border: 2px solid color-mix(in oklch, var(--color-base-content, #a6adbb) 50%, transparent);
      border-radius: 50%;
      cursor: crosshair;
      transition: all 0.15s ease;
    }

    .socket:hover {
      background: var(--color-primary, #7c3aed);
      border-color: var(--color-primary, #7c3aed);
      transform: scale(1.3);
    }
  `;

  render() {
    return html`<div class="socket" title="${this.data?.name || ""}"></div>`;
  }
}

customElements.define("storyarn-socket", StoryarnSocket);
