/**
 * Styles for StoryarnNode LitElement component.
 *
 * Only styles that CANNOT be expressed as Tailwind utilities remain here:
 * - Box shadows using color-mix() with dynamic --node-color
 * - Debug @keyframes animations and :host() selectors
 * - Response indicator ::after tooltip pseudo-element
 * - Socket negative margins (structural for Rete.js)
 * - Inline edit field-sizing (no Tailwind equivalent)
 *
 * Everything else is expressed as Tailwind classes in the Lit templates.
 */

import { css } from "lit";

export const storyarnNodeStyles = css`
  :host {
    display: block;
  }

  /* --- Node shell shadows (dynamic --node-color) --- */

  .node {
    box-shadow:
      0 4px 6px -1px rgb(0 0 0 / 0.1),
      0 2px 4px -2px rgb(0 0 0 / 0.1),
      0 0 12px 1px color-mix(in oklch, var(--node-color, #666) 12%, transparent);
    transition: box-shadow 0.2s;
  }

  .node:hover {
    box-shadow:
      0 10px 15px -3px rgb(0 0 0 / 0.1),
      0 4px 6px -4px rgb(0 0 0 / 0.1),
      0 0 18px 2px color-mix(in oklch, var(--node-color, #666) 18%, transparent);
  }

  .node.selected {
    box-shadow:
      0 0 0 3px color-mix(in oklch, var(--color-primary) 50%, transparent),
      0 4px 6px -1px rgb(0 0 0 / 0.1),
      0 0 16px 2px color-mix(in oklch, var(--node-color, #666) 15%, transparent);
  }

  /* --- Socket negative margins (structural for Rete.js) --- */

  .sockets-row .input-socket { margin-left: -6px; }
  .sockets-row .output-socket { margin-right: -6px; }
  .input-socket { margin-left: -6px; }
  .output-socket { margin-right: -6px; }

  /* --- Response indicator tooltip (::after pseudo-element) --- */

  .response-indicator {
    position: relative;
    width: 3px;
    align-self: stretch;
    border-radius: 2px;
    flex-shrink: 0;
    margin-right: 2px;
    cursor: default;
  }

  /* Counter-scale tooltip to stay visually constant at any zoom level */
  .tooltip::before {
    font-size: calc(var(--tooltip-font-size, 0.75rem) / var(--canvas-zoom, 1));
  }

  /* --- Inline edit fields (field-sizing, color-mix placeholders) --- */

  .inline-input {
    border-bottom: 1px solid color-mix(in oklch, var(--color-base-300) 50%, transparent);
    color: color-mix(in oklch, var(--color-base-content) 55%, transparent);
  }

  .inline-input:focus {
    border-bottom-color: var(--color-primary);
  }

  .inline-input::placeholder {
    color: color-mix(in oklch, var(--color-base-content) 30%, transparent);
  }

  .inline-textarea {
    color: color-mix(in oklch, var(--color-base-content) 85%, transparent);
    field-sizing: content;
    min-height: 2lh;
  }

  .inline-textarea::placeholder {
    color: color-mix(in oklch, var(--color-base-content) 30%, transparent);
  }

  /* --- Inline speaker trigger --- */

  .inline-speaker-trigger:hover {
    opacity: 0.85;
  }

  .inline-speaker-trigger svg {
    flex-shrink: 0;
    opacity: 0.7;
  }

  /* --- Error badge (color-mix background) --- */

  .error-badge {
    background: color-mix(in oklch, var(--color-error) 20%, transparent);
    color: var(--color-error);
  }

  /* --- Nav link hover --- */

  .nav-link:hover {
    color: var(--color-primary);
  }

  .nav-jumps-link:hover {
    opacity: 1;
    color: var(--color-primary);
  }

  /* --- Debug animations & host selectors --- */

  :host(.nav-highlight) .node {
    animation: nav-pulse 0.6s ease-in-out 4;
  }

  @keyframes nav-pulse {
    0%, 100% {
      box-shadow: 0 0 0 3px var(--highlight-color), 0 0 12px 2px var(--highlight-color);
    }
    50% {
      box-shadow: 0 0 0 6px color-mix(in srgb, var(--highlight-color) 50%, transparent),
                  0 0 20px 4px color-mix(in srgb, var(--highlight-color) 30%, transparent);
    }
  }

  :host(.debug-current) .node {
    animation: debug-pulse 1.5s ease-in-out infinite;
    border-color: color-mix(in oklch, var(--color-primary) 60%, transparent);
  }

  :host(.debug-visited) .node {
    border-color: color-mix(in oklch, var(--color-success) 40%, transparent);
  }

  :host(.debug-waiting) .node {
    animation: debug-pulse-warning 1.5s ease-in-out infinite;
    border-color: color-mix(in oklch, var(--color-warning) 60%, transparent);
  }

  :host(.debug-error) .node {
    border-color: color-mix(in oklch, var(--color-error) 50%, transparent);
    box-shadow: 0 0 0 2px color-mix(in oklch, var(--color-error) 15%, transparent);
  }

  :host(.debug-breakpoint) .node::after {
    content: '';
    position: absolute;
    top: -3px;
    right: -3px;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--color-error);
    box-shadow: 0 0 4px color-mix(in oklch, var(--color-error) 50%, transparent);
    z-index: 10;
  }

  @keyframes debug-pulse {
    0%, 100% {
      box-shadow: 0 0 0 3px color-mix(in oklch, var(--color-primary) 35%, transparent);
    }
    50% {
      box-shadow: 0 0 0 6px color-mix(in oklch, var(--color-primary) 12%, transparent),
                  0 0 14px color-mix(in oklch, var(--color-primary) 8%, transparent);
    }
  }

  @keyframes debug-pulse-warning {
    0%, 100% {
      box-shadow: 0 0 0 3px color-mix(in oklch, var(--color-warning) 35%, transparent);
    }
    50% {
      box-shadow: 0 0 0 6px color-mix(in oklch, var(--color-warning) 12%, transparent),
                  0 0 14px color-mix(in oklch, var(--color-warning) 8%, transparent);
    }
  }
`;
