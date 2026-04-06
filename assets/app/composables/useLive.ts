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
      ) => {
        console.warn(`[useLive] pushEvent("${event}") called outside LiveView`, payload);
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
     */
    pushEvent: (
      event: string,
      payload: Record<string, unknown> = {},
      callback?: (reply: Record<string, unknown>) => void,
    ) => {
      $live.pushEvent(event, payload, callback);
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
