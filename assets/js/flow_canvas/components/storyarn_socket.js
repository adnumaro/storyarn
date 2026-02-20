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
      background: oklch(var(--bc, 0.7 0 0) / 0.25);
      border: 2px solid oklch(var(--bc, 0.7 0 0) / 0.5);
      border-radius: 50%;
      cursor: crosshair;
      transition: all 0.15s ease;
    }

    .socket:hover {
      background: oklch(var(--p, 0.6 0.2 250));
      border-color: oklch(var(--p, 0.6 0.2 250));
      transform: scale(1.3);
    }
  `;

  render() {
    return html`<div class="socket" title="${this.data?.name || ""}"></div>`;
  }
}

customElements.define("storyarn-socket", StoryarnSocket);
