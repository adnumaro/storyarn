/**
 * Styles for StoryarnNode LitElement component.
 * Uses daisyUI CSS variables (they pierce Shadow DOM).
 */

import { css } from "lit";

export const storyarnNodeStyles = css`
  :host {
    display: block;
  }

  .node {
    position: relative;
    background: oklch(var(--b1, 0.2 0 0));
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
    box-shadow: 0 0 0 3px oklch(var(--p, 0.6 0.2 250) / 0.5), 0 4px 6px -1px rgb(0 0 0 / 0.1);
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
    color: oklch(var(--bc, 0.8 0 0) / 0.7);
    margin-left: 4px;
  }

  .socket-label-right {
    font-size: 11px;
    color: oklch(var(--bc, 0.8 0 0) / 0.7);
    margin-left: auto;
    margin-right: 4px;
  }

  .socket-row {
    display: flex;
    align-items: center;
    padding: 4px 0;
    font-size: 11px;
    color: oklch(var(--bc, 0.8 0 0) / 0.7);
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
    color: oklch(var(--bc, 0.8 0 0) / 0.8);
    padding: 8px 12px;
    max-width: 200px;
    border-bottom: 1px solid oklch(var(--bc, 0.8 0 0) / 0.1);
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
    color: oklch(var(--bc, 0.8 0 0) / 0.5);
    font-size: 10px;
    padding: 4px 12px;
    max-width: 200px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    background: oklch(var(--bc, 0.8 0 0) / 0.03);
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
    background: oklch(var(--wa, 0.8 0.15 80) / 0.2);
    color: oklch(var(--wa, 0.8 0.15 80));
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
    background: oklch(var(--er, 0.65 0.25 25) / 0.2);
    color: oklch(var(--er, 0.65 0.25 25));
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

  .logic-indicator.input-condition {
    color: rgba(255, 255, 255, 0.9);
  }

  .logic-indicator.output-instruction {
    color: rgba(255, 255, 255, 0.9);
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
    border-color: oklch(var(--p, 0.6 0.2 250) / 0.6);
  }

  /* Debug: visited node — subtle success border */
  :host(.debug-visited) .node {
    border-color: oklch(var(--su, 0.75 0.15 150) / 0.4);
  }

  /* Debug: waiting for input — pulsing warning border */
  :host(.debug-waiting) .node {
    animation: debug-pulse-warning 1.5s ease-in-out infinite;
    border-color: oklch(var(--wa, 0.8 0.15 80) / 0.6);
  }

  /* Debug: error node — error border */
  :host(.debug-error) .node {
    border-color: oklch(var(--er, 0.65 0.25 25) / 0.5);
    box-shadow: 0 0 0 2px oklch(var(--er, 0.65 0.25 25) / 0.15);
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
    background: oklch(var(--er, 0.65 0.25 25));
    box-shadow: 0 0 4px oklch(var(--er, 0.65 0.25 25) / 0.5);
    z-index: 10;
  }

  @keyframes debug-pulse {
    0%, 100% {
      box-shadow: 0 0 0 3px oklch(var(--p, 0.6 0.2 250) / 0.35);
    }
    50% {
      box-shadow: 0 0 0 6px oklch(var(--p, 0.6 0.2 250) / 0.12),
                  0 0 14px oklch(var(--p, 0.6 0.2 250) / 0.08);
    }
  }

  @keyframes debug-pulse-warning {
    0%, 100% {
      box-shadow: 0 0 0 3px oklch(var(--wa, 0.8 0.15 80) / 0.35);
    }
    50% {
      box-shadow: 0 0 0 6px oklch(var(--wa, 0.8 0.15 80) / 0.12),
                  0 0 14px oklch(var(--wa, 0.8 0.15 80) / 0.08);
    }
  }

  .nav-link {
    cursor: pointer;
    text-decoration: underline dotted;
    text-underline-offset: 2px;
  }

  .nav-link:hover {
    color: oklch(var(--p));
  }

  .nav-jumps-link {
    font-size: 10px;
    opacity: 0.5;
    cursor: pointer;
    padding: 2px 12px 4px;
  }

  .nav-jumps-link:hover {
    opacity: 1;
    color: oklch(var(--p));
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
