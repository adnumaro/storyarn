/**
 * Stub for the app's `_live_vue` injection (see assets/app/shared/composables/useLive.ts).
 * Components that push LiveView events keep working in Claude Design previews:
 * events are logged, never sent, and reply callbacks are not invoked.
 */
import type { App } from "vue";

export interface LiveStub {
  pushEvent: (
    event: string,
    payload?: Record<string, unknown>,
    callback?: (reply: Record<string, unknown>) => void,
    onError?: (error: unknown) => void,
  ) => void;
  handleEvent: (
    event: string,
    callback: (payload: Record<string, unknown>) => void,
  ) => number | undefined;
  removeHandleEvent: (ref: number) => void;
  upload: (name: string, files: FileList) => void;
}

export function makeLiveStub(): LiveStub {
  return {
    pushEvent(event, payload) {
      console.debug("[storyarn-ds] pushEvent (no-op in designs):", event, payload);
    },
    handleEvent(event) {
      console.debug("[storyarn-ds] handleEvent registered (no-op in designs):", event);
      return undefined;
    },
    removeHandleEvent() {},
    upload() {},
  };
}

export function installLiveStub(app: App): void {
  app.provide("_live_vue", makeLiveStub());
}
