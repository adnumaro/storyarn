<script setup>
defineProps({
  width: { type: Number, default: 1000 },
  height: { type: Number, default: 1000 },
});
</script>

<template>
  <div class="pt-2 border-t border-border">
    <label class="text-xs font-medium text-muted-foreground">Dimensions</label>
    <p class="text-xs text-muted-foreground/70">
      {{ width || 1000 }} &times; {{ height || 1000 }} px
    </p>
  </div>
</template>
