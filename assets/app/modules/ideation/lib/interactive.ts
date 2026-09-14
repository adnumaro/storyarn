/** Elements the canvas leaves alone: form controls, links and its own chrome. */
export const INTERACTIVE =
  'input, textarea, select, button, a, [contenteditable="true"], [role="textbox"], [data-canvas-chrome]';

export function interactiveTarget(target: EventTarget | null): boolean {
  return target instanceof Element && Boolean(target.closest(INTERACTIVE));
}

/**
 * A native event yields to microtasks between listeners, so a descendant that
 * re-renders on the event (the round question turning into an input) detaches
 * `event.target` before the canvas sees it. The dispatch path is fixed up front.
 */
export function interactivePath(event: Event): boolean {
  return event.composedPath().some((node) => node instanceof Element && node.matches(INTERACTIVE));
}
