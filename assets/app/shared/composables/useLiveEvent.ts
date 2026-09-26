import { getCurrentScope, onScopeDispose } from "vue";
import { useLive, type LiveInterface } from "./useLive";

/**
 * Handles a server-pushed LiveView event for as long as the calling component
 * or effect scope lives. The handler is removed when the scope is disposed, so
 * a component mounted again (a tab opened twice) never runs it twice.
 *
 * Pass `live` when the caller already holds one; otherwise it is resolved here,
 * which requires a component setup.
 */
export function useLiveEvent(
  event: string,
  handler: (payload: Record<string, unknown>) => void,
  live: LiveInterface = useLive(),
): void {
  const handlerRef = live.handleEvent(event, handler);

  if (getCurrentScope()) {
    onScopeDispose(() => {
      if (handlerRef !== undefined) live.removeHandleEvent(handlerRef);
    });
  }
}
