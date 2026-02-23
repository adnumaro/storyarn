/**
 * Styles for StoryarnNode LitElement component.
 * Uses daisyUI v5 CSS variables (they pierce Shadow DOM).
 */

import { css } from "lit";

export const storyarnNodeStyles = css`
  :host {
    display: block;
  }

  .node {
    position: relative;
    background: var(--color-base-100, #1d232a);
    border-radius: 8px;
    min-width: 180px;
    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
    border: 1.5px solid var(--node-border-color, transparent);
    transition: box-shadow 0.2s;
  }

  .node:hover {
    box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
  }

  .node.selected {
    box-shadow: 0 0 0 3px color-mix(in oklch, var(--color-primary, #7c3aed) 50%, transparent), 0 4px 6px -1px rgb(0 0 0 / 0.1);
  }

  .header {
    padding: 8px 12px;
    border-radius: 6px 6px 0 0;
    display: flex;
    align-items: center;
    gap: 8px;
    color: white;
    font-weight: 500;
    font-size: 13px;
  }

  .icon {
    display: flex;
    align-items: center;
  }

  .content {
    padding: 4px 0;
  }

  .sockets-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 4px 0;
  }

  .sockets-row .input-socket {
    margin-left: -10px;
  }

  .sockets-row .output-socket {
    margin-right: -10px;
  }

  .socket-label-left {
    font-size: 11px;
    color: color-mix(in oklch, var(--color-base-content, #a6adbb) 70%, transparent);
    margin-left: 4px;
  }

  .socket-label-right {
    font-size: 11px;
    color: color-mix(in oklch, var(--color-base-content, #a6adbb) 70%, transparent);
    margin-left: auto;
    margin-right: 4px;
  }

  .socket-row {
    display: flex;
    align-items: center;
    padding: 4px 0;
    font-size: 11px;
    color: color-mix(in oklch, var(--color-base-content, #a6adbb) 70%, transparent);
  }

  .socket-row.input {
    justify-content: flex-start;
    padding-left: 0;
  }

  .socket-row.output {
    justify-content: flex-end;
    padding-right: 0;
  }

  .socket-row .label {
    padding: 0 8px;
  }

  .input-socket {
    margin-left: -10px;
  }

  .output-socket {
    margin-right: -10px;
  }

  .node-data {
    font-size: 11px;
    color: color-mix(in oklch, var(--color-base-content, #a6adbb) 80%, transparent);
    padding: 8px 12px;
    max-width: 200px;
    border-bottom: 1px solid color-mix(in oklch, var(--color-base-content, #a6adbb) 10%, transparent);
    word-break: break-word;
  }

  .node-data-text {
    display: -webkit-box;
    -webkit-line-clamp: 4;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-height: 1.4;
  }

  .stage-directions {
    font-style: italic;
    color: color-mix(in oklch, var(--color-base-content, #a6adbb) 50%, transparent);
    font-size: 10px;
    padding: 4px 12px;
    max-width: 200px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    background: color-mix(in oklch, var(--color-base-content, #a6adbb) 3%, transparent);
  }

  .speaker-avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    object-fit: cover;
    flex-shrink: 0;
  }

  .speaker-name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .condition-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 14px;
    height: 14px;
    font-size: 10px;
    font-weight: bold;
    background: color-mix(in oklch, var(--color-warning, #fbbd23) 20%, transparent);
    color: var(--color-warning, #fbbd23);
    border-radius: 50%;
    margin-right: 2px;
  }

  .error-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 14px;
    height: 14px;
    font-size: 10px;
    font-weight: bold;
    background: color-mix(in oklch, var(--color-error, #f87171) 20%, transparent);
    color: var(--color-error, #f87171);
    border-radius: 50%;
    margin-right: 2px;
    cursor: help;
  }

  .audio-indicator {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    margin-left: auto;
    opacity: 0.8;
  }

  .audio-indicator svg {
    width: 12px;
    height: 12px;
  }

  .header-indicators {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-left: auto;
  }

  .logic-indicator {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 10px;
    opacity: 0.9;
  }


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

  /* Debug: current node — pulsing primary border */
  :host(.debug-current) .node {
    animation: debug-pulse 1.5s ease-in-out infinite;
    border-color: color-mix(in oklch, var(--color-primary, #7c3aed) 60%, transparent);
  }

  /* Debug: visited node — subtle success border */
  :host(.debug-visited) .node {
    border-color: color-mix(in oklch, var(--color-success, #36d399) 40%, transparent);
  }

  /* Debug: waiting for input — pulsing warning border */
  :host(.debug-waiting) .node {
    animation: debug-pulse-warning 1.5s ease-in-out infinite;
    border-color: color-mix(in oklch, var(--color-warning, #fbbd23) 60%, transparent);
  }

  /* Debug: error node — error border */
  :host(.debug-error) .node {
    border-color: color-mix(in oklch, var(--color-error, #f87171) 50%, transparent);
    box-shadow: 0 0 0 2px color-mix(in oklch, var(--color-error, #f87171) 15%, transparent);
  }

  /* Debug: breakpoint — red dot at top-right corner */
  :host(.debug-breakpoint) .node::after {
    content: '';
    position: absolute;
    top: -3px;
    right: -3px;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--color-error, #f87171);
    box-shadow: 0 0 4px color-mix(in oklch, var(--color-error, #f87171) 50%, transparent);
    z-index: 10;
  }

  @keyframes debug-pulse {
    0%, 100% {
      box-shadow: 0 0 0 3px color-mix(in oklch, var(--color-primary, #7c3aed) 35%, transparent);
    }
    50% {
      box-shadow: 0 0 0 6px color-mix(in oklch, var(--color-primary, #7c3aed) 12%, transparent),
                  0 0 14px color-mix(in oklch, var(--color-primary, #7c3aed) 8%, transparent);
    }
  }

  @keyframes debug-pulse-warning {
    0%, 100% {
      box-shadow: 0 0 0 3px color-mix(in oklch, var(--color-warning, #fbbd23) 35%, transparent);
    }
    50% {
      box-shadow: 0 0 0 6px color-mix(in oklch, var(--color-warning, #fbbd23) 12%, transparent),
                  0 0 14px color-mix(in oklch, var(--color-warning, #fbbd23) 8%, transparent);
    }
  }

  .nav-link {
    cursor: pointer;
    text-decoration: underline dotted;
    text-underline-offset: 2px;
  }

  .nav-link:hover {
    color: var(--color-primary, #7c3aed);
  }

  .nav-jumps-link {
    font-size: 10px;
    opacity: 0.5;
    cursor: pointer;
    padding: 2px 12px 4px;
  }

  .nav-jumps-link:hover {
    opacity: 1;
    color: var(--color-primary, #7c3aed);
  }

  /* Simplified LOD — compact node */
  .node.simplified {
    min-width: 120px;
  }

  .node.simplified .content {
    padding: 2px 0;
  }

  .node.simplified .socket-row {
    padding: 2px 0;
  }
`;
