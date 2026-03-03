/**
 * StoryarnSocket - Custom LitElement component for rendering node sockets.
 */

import { css, html, LitElement } from "lit";
import { adoptTailwind } from "../../utils/shadow_styles.js";

export class StoryarnSocket extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
    };
  }

  connectedCallback() {
    super.connectedCallback();
    adoptTailwind(this.shadowRoot);
  }

  static styles = css`
    :host {
      display: inline-block;
    }
  `;

  render() {
    return html`<div
      class="size-2.5 bg-base-content/25 border-2 border-base-content/50 rounded-full
             cursor-crosshair transition-all duration-150
             hover:bg-primary hover:border-primary hover:scale-[1.3]"
      title="${this.data?.name || ""}"
    ></div>`;
  }
}

customElements.define("storyarn-socket", StoryarnSocket);
