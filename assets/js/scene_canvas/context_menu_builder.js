/**
 * Shared context menu item builders.
 * All label strings come from i18n passed from the server.
 */

export function editPropertiesItem(type, id, hook, i18n) {
  return {
    label: i18n.edit_properties,
    action: () => hook.pushEvent("select_element", { type, id }),
  };
}

export function bringToFrontItem(type, id, maxPos, hook, i18n) {
  return {
    label: i18n.bring_to_front,
    action: () =>
      hook.pushEvent(`update_${type}`, {
        id: String(id),
        field: "position",
        value: String(maxPos + 1),
      }),
  };
}

export function sendToBackItem(type, id, minPos, hook, i18n) {
  return {
    label: i18n.send_to_back,
    action: () =>
      hook.pushEvent(`update_${type}`, {
        id: String(id),
        field: "position",
        value: String(minPos - 1),
      }),
  };
}

export function lockToggleItem(type, id, isLocked, hook, i18n) {
  return {
    label: isLocked ? i18n.unlock : i18n.lock,
    action: () =>
      hook.pushEvent(`update_${type}`, {
        id: String(id),
        field: "locked",
        value: String(!isLocked),
      }),
  };
}

export function deleteItem(type, id, hook, i18n) {
  return {
    label: i18n.delete,
    danger: true,
    action: () => hook.pushEvent(`delete_${type}`, { id: String(id) }),
  };
}
