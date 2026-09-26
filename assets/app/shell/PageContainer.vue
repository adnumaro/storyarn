<script setup lang="ts">
/**
 * The page of a utility screen (dashboards, lists, localization, a sheet): the
 * direct child of the layout's `main`. It fills the height and scrolls, owns
 * the page padding, and lays out the screen's sections, so every screen spaces
 * them alike and pages carry no layout classes of their own. Canvas screens and
 * Settings keep their own layouts.
 */
const {
  width = "contained",
  layout = "stack",
  fill = false,
} = defineProps<{
  /** `contained` centres the content at 1200 px at most; `full` uses the whole width. */
  width?: "contained" | "full";
  /** `stack` places sections one under another; `aside` adds a 360 px side column on desktop. */
  layout?: "stack" | "aside";
  /** The last section takes the height left over, for content that scrolls on its own. */
  fill?: boolean;
}>();
</script>
<template>
  <div
    data-page-container
    :data-width="width"
    :data-layout="layout"
    class="h-full min-h-0 w-full overflow-y-auto px-4 py-4 lg:px-6 lg:py-6"
  >
    <div
      data-page-sections
      :class="[
        'w-full gap-6',
        width === 'contained' && 'mx-auto max-w-[1200px]',
        layout === 'aside'
          ? 'grid items-start lg:grid-cols-[minmax(0,1fr)_360px]'
          : 'flex flex-col',
        fill && 'h-full min-h-0 [&>:last-child]:min-h-0 [&>:last-child]:flex-1',
      ]"
    >
      <slot />
    </div>
  </div>
</template>
