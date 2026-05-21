import type { Ref } from "vue";
import { isFunction } from "@tanstack/vue-table";

export function valueUpdater<T>(updaterOrValue: T | ((old: T) => T), ref: Ref<T>) {
  ref.value = isFunction(updaterOrValue) ? updaterOrValue(ref.value) : updaterOrValue;
}
