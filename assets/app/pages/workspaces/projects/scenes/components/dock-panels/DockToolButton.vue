<script setup>
const props = defineProps({
  icon: { type: [Object, Function], required: true },
  active: { type: Boolean, default: false },
  tooltipTitle: { type: String, required: true },
  tooltipDescription: { type: String, default: "" },
  tag: { type: String, default: "button" },
  href: { type: String, default: null },
});

const emit = defineEmits(["click"]);
</script>

<template>
  <div class="v2-dock-item group relative">
    <component
      :is="tag"
      :type="tag === 'button' ? 'button' : undefined"
      :href="href"
      :data-phx-link="tag === 'a' ? 'redirect' : undefined"
      :data-phx-link-state="tag === 'a' ? 'push' : undefined"
      class="v2-dock-btn"
      :class="{ 'v2-dock-btn-active': active }"
      @click="emit('click')"
    >
      <component :is="icon" class="size-5" />
    </component>
    <div class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ tooltipTitle }}</div>
      <div v-if="tooltipDescription" class="text-xs text-muted-foreground leading-relaxed">
        {{ tooltipDescription }}
      </div>
    </div>
  </div>
</template>
