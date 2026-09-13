export const OPEN_COMMENTS_EVENT = "storyarn:open-comments";
export const COMMENTS_VISIBILITY_EVENT = "storyarn:comments-visibility";

export function openComments(): void {
  window.dispatchEvent(new Event(OPEN_COMMENTS_EVENT));
}

export function notifyCommentsVisibility(open: boolean): void {
  window.dispatchEvent(new CustomEvent(COMMENTS_VISIBILITY_EVENT, { detail: { open } }));
}
