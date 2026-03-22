/**
 * Typed wrapper around LiveVue's $live for pushing events to Phoenix LiveView.
 *
 * Usage:
 *   const live = useLive()
 *   live.pushEvent("update_pin", { id: 1, field: "label", value: "New Label" })
 *   live.handleEvent("pin_updated", (payload) => { ... })
 */

import { getCurrentInstance } from "vue";

export function useLive() {
	const instance = getCurrentInstance();
	const $live = instance?.proxy?.$live;

	if (!$live) {
		// Return a no-op stub when used outside LiveView (e.g., Storybook)
		return {
			pushEvent: (event, payload, callback) => {
				console.warn(
					`[useLive] pushEvent("${event}") called outside LiveView`,
					payload,
				);
				callback?.({});
			},
			handleEvent: (event, callback) => {
				console.warn(
					`[useLive] handleEvent("${event}") registered outside LiveView`,
				);
			},
			upload: () => {
				console.warn("[useLive] upload() called outside LiveView");
			},
		};
	}

	return {
		/**
		 * Push an event to the LiveView server.
		 * @param {string} event - Event name (must match handle_event in LiveView)
		 * @param {object} payload - Event payload
		 * @param {function} [callback] - Optional callback with server reply
		 */
		pushEvent: (event, payload = {}, callback) => {
			$live.pushEvent(event, payload, callback);
		},

		/**
		 * Register a handler for server-pushed events.
		 * @param {string} event - Event name (from push_event in LiveView)
		 * @param {function} callback - Handler function
		 */
		handleEvent: (event, callback) => {
			$live.handleEvent(event, callback);
		},

		/**
		 * Upload files via LiveView uploads.
		 * @param {string} name - Upload name
		 * @param {FileList} files - Files to upload
		 */
		upload: (name, files) => {
			$live.upload(name, files);
		},
	};
}
