/** Base attributes shared by all screenplay nodes. */
export const BASE_ATTRS = {
  elementId: {
    default: null,
    parseHTML: (el) => el.dataset.elementId || null,
    renderHTML: () => ({}),
  },
  data: {
    default: {},
    parseHTML: () => ({}),
    renderHTML: () => ({}),
  },
};
