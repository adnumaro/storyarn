/**
 * Typed wrapper around LiveVue's $live for pushing events to Phoenix LiveView.
 *
 * Usage:
 *   const live = useLive()
 *   live.pushEvent("update_pin", { id: 1, field: "label", value: "New Label" })
 *   live.handleEvent("pin_updated", (payload) => { ... })
 */

import { getCurrentInstance } from "vue";

export interface LiveInterface {
  pushEvent: (
    event: string,
    payload?: Record<string, unknown>,
    callback?: (reply: Record<string, unknown>) => void,
    onError?: (error: unknown) => void,
  ) => void;
  handleEvent: (event: string, callback: (payload: Record<string, unknown>) => void) => void;
  upload: (name: string, files: FileList) => void;
}

export function useLive(): LiveInterface {
  const instance = getCurrentInstance();
  const globalProps = instance?.appContext.config.globalProperties;
  const $live = globalProps?.$live as LiveInterface | undefined;

  if (!$live) {
    // Return a no-op stub when used outside LiveView (e.g., Storybook)
    return {
      pushEvent: (
        event: string,
        payload?: Record<string, unknown>,
        callback?: (reply: Record<string, unknown>) => void,
        onError?: (error: unknown) => void,
      ) => {
        console.warn(`[useLive] pushEvent("${event}") called outside LiveView`, payload);
        onError?.(new Error("LiveView is unavailable"));
        callback?.({});
      },
      handleEvent: (event: string, _callback: (payload: Record<string, unknown>) => void) => {
        console.warn(`[useLive] handleEvent("${event}") registered outside LiveView`);
      },
      upload: () => {
        console.warn("[useLive] upload() called outside LiveView");
      },
    };
  }

  return {
    /**
     * Push an event to the LiveView server.
     *
     * `$live.pushEvent` is fire-and-forget (no promise, no retry). It throws
     * when the socket is gone (typical case: cleanup pushEvent from
     * `onUnmounted` during navigation, where LiveView tore down before the
     * Vue tree). The caller cannot recover; we catch and warn so an
     * unhandled promise rejection doesn't break subsequent teardown steps.
     */
    pushEvent: (
      event: string,
      payload: Record<string, unknown> = {},
      callback?: (reply: Record<string, unknown>) => void,
      onError?: (error: unknown) => void,
    ) => {
      try {
        $live.pushEvent(event, payload, callback);
      } catch (err) {
        console.warn(
          `[useLive] pushEvent("${event}") dropped:`,
          err instanceof Error ? err.message : err,
        );
        onError?.(err);
      }
    },

    /**
     * Register a handler for server-pushed events.
     */
    handleEvent: (event: string, callback: (payload: Record<string, unknown>) => void) => {
      $live.handleEvent(event, callback);
    },

    /**
     * Upload files via LiveView uploads.
     */
    upload: (name: string, files: FileList) => {
      $live.upload(name, files);
    },
  };
}
