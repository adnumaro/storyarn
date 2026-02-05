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
`;
