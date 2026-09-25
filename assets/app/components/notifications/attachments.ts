import type { Component } from "vue";

/**
 * Renderers for notification attachments, registered by the domains that send
 * them. A renderer draws the whole body of its notification below the actor:
 * the sentence, the attachment and its footer. It receives `notification`,
 * `data` and `when` (the relative time) and emits `open` with whether the
 * notification should stay unread.
 */
const renderers = new Map<string, Component>();

export function registerNotificationAttachment(type: string, renderer: Component): void {
  renderers.set(type, renderer);
}

export function notificationAttachment(type: string): Component | undefined {
  return renderers.get(type);
}
