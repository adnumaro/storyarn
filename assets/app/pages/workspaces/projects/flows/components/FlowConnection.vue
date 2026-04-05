<script setup>
import { computed } from "vue";

const { path, data } = defineProps({
  path: { type: String, default: "" },
  data: { type: Object, default: null },
});

/**
 * Calculate midpoint of cubic bezier path at t=0.5 for label positioning.
 */
const midpoint = computed(() => {
  if (!path || !data?.label) return null;

  const m = path.match(
    /M\s*([\d.-]+)[,\s]*([\d.-]+)\s*C\s*([\d.-]+)[,\s]*([\d.-]+)\s*([\d.-]+)[,\s]*([\d.-]+)\s*([\d.-]+)[,\s]*([\d.-]+)/,
  );
  if (!m) return null;

  const [, x0, y0, x1, y1, x2, y2, x3, y3] = m.map(Number);
  const t = 0.5;
  const mt = 1 - t;
  return {
    x: mt ** 3 * x0 + 3 * mt ** 2 * t * x1 + 3 * mt * t ** 2 * x2 + t ** 3 * x3,
    y: mt ** 3 * y0 + 3 * mt ** 2 * t * y1 + 3 * mt * t ** 2 * y2 + t ** 3 * y3,
  };
});

const labelWidth = computed(() => (data?.label ? Math.min(data.label.length * 6 + 10, 80) : 0));
</script>

<template>
  <svg
    data-testid="connection"
    class="overflow-visible absolute pointer-events-none"
    style="width: 9999px; height: 9999px"
  >
    <!-- Invisible hit area -->
    <path
      :d="path"
      fill="none"
      stroke="transparent"
      stroke-width="20"
      class="pointer-events-auto [&:hover+path]:!stroke-primary [&:hover+path]:!stroke-[3px]"
    />
    <!-- Visible line -->
    <path
      :d="path"
      fill="none"
      class="stroke-foreground/40 stroke-2 pointer-events-none transition-[stroke,stroke-width] duration-150"
    />
    <!-- Label at midpoint -->
    <g v-if="midpoint && data?.label" :transform="`translate(${midpoint.x}, ${midpoint.y})`">
      <rect
        class="fill-background stroke-foreground/30"
        stroke-width="1"
        rx="3"
        ry="3"
        :x="-labelWidth / 2"
        y="-9"
        :width="labelWidth"
        height="18"
      />
      <text
        class="fill-foreground text-[10px]"
        font-family="system-ui, sans-serif"
        dominant-baseline="middle"
        text-anchor="middle"
      >
        {{ data.label }}
      </text>
    </g>
  </svg>
</template>
