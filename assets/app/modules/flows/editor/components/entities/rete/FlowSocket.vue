<script setup lang="ts">
interface SocketData {
  name?: string;
}

const { data = null } = defineProps<{
  data: SocketData | null;
}>();
</script>

<template>
  <div
    class="size-2.5 bg-foreground/25 border-2 border-foreground/50 rounded-full cursor-crosshair transition-all duration-150 hover:bg-primary hover:border-primary hover:scale-[1.3]"
    :title="data?.name || ''"
  />
</template>
