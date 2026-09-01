/**
 * Theme access for adapter content that reka-ui teleports to <body> — outside
 * the design's `.dark` subtree. Adapters put `dark` on their floating content
 * root so tokens re-resolve there when the wrapped instance mounted inside a
 * dark subtree.
 */
import { computed, inject, ref, type ComputedRef } from "vue";
import { DS_THEME_KEY, type DsTheme } from "../harness/host";

export function useContentThemeClass(): ComputedRef<string> {
  const theme = inject<DsTheme>(DS_THEME_KEY, { isDark: ref(false) });
  return computed(() => (theme.isDark.value ? "dark" : ""));
}
