/**
 * Target-aware event dispatcher for LiveView hooks.
 * Checks for data-phx-target or data-target attributes on the hook's element
 * and dispatches to the correct pushEvent/pushEventTo method.
 *
 * @param {Object} hook - The LiveView hook instance (this)
 * @param {string} eventName - The event name to push
 * @param {Object} [payload={}] - The event payload
 */
export function pushWithTarget(hook, eventName, payload = {}) {
  const target = hook.el.dataset.phxTarget || hook.el.dataset.target;
  if (target) {
    hook.pushEventTo(target, eventName, payload);
  } else {
    hook.pushEvent(eventName, payload);
  }
}
