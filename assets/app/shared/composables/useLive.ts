/**
 * Typed wrapper around LiveVue's $live for pushing events to Phoenix LiveView.
 *
 * Usage:
 *   const live = useLive()
 *   live.pushEvent("update_pin", { id: 1, field: "label", value: "New Label" })
 *   live.handleEvent("pin_updated", (payload) => { ... })
 */

import { getCurrentInstance, inject } from "vue";

export interface LiveInterface {
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

interface PromisePushEventTarget {
  liveSocket: unknown;
  pushEvent: (event: string, payload?: Record<string, unknown>) => Promise<Record<string, unknown>>;
}

function supportsPromisePushEvent(live: LiveInterface): boolean {
  return "liveSocket" in live;
}

export function useLive(): LiveInterface {
  // LiveVue replaces this injection for components teleported with `v-inject`,
  // so events keep targeting the LiveView that owns the injected component.
  // The app-global hook belongs to the host Vue tree and is only a fallback.
  const injectedLive = inject<LiveInterface | undefined>("_live_vue", undefined);
  const instance = getCurrentInstance();
  const globalProps = instance?.appContext.config.globalProperties;
  const $live = injectedLive ?? (globalProps?.$live as LiveInterface | undefined);

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
        return undefined;
      },
      removeHandleEvent: () => {},
      upload: () => {
        console.warn("[useLive] upload() called outside LiveView");
      },
    };
  }

  return {
    /**
     * Push an event to the LiveView server.
     *
     * Phoenix only exposes transport failures through the Promise overload;
     * its callback overload deliberately consumes rejections. Use the Promise
     * overload whenever a caller supplied `onError`, while retaining callback
     * compatibility for app-level adapters and tests that do not expose the
     * underlying LiveView hook.
     */
    pushEvent: (
      event: string,
      payload: Record<string, unknown> = {},
      callback?: (reply: Record<string, unknown>) => void,
      onError?: (error: unknown) => void,
    ) => {
      const reportError = (err: unknown) => {
        console.warn(
          `[useLive] pushEvent("${event}") dropped:`,
          err instanceof Error ? err.message : err,
        );
        onError?.(err);
      };

      try {
        if (onError && supportsPromisePushEvent($live)) {
          const promiseLive = $live as unknown as PromisePushEventTarget;

          void promiseLive.pushEvent(event, payload).then(
            (reply) => callback?.(reply),
            (err) => reportError(err),
          );
        } else {
          $live.pushEvent(event, payload, callback);
        }
      } catch (err) {
        reportError(err);
      }
    },

    /**
     * Register a handler for server-pushed events.
     */
    handleEvent: (event: string, callback: (payload: Record<string, unknown>) => void) => {
      return $live.handleEvent(event, callback);
    },

    /**
     * Remove a previously registered server-event handler.
     */
    removeHandleEvent: (ref: number) => {
      $live.removeHandleEvent(ref);
    },

    /**
     * Upload files via LiveView uploads.
     */
    upload: (name: string, files: FileList) => {
      $live.upload(name, files);
    },
  };
}
