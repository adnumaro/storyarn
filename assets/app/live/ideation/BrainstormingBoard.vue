<script setup lang="ts">
import { BrainstormingWorkspace, type Board } from "@modules/ideation";
const { board, baseUrl } = defineProps<{ board: Board; baseUrl: string }>();
</script>
<template><BrainstormingWorkspace :board="board" :base-url="baseUrl" /></template>
