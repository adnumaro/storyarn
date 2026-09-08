<script setup lang="ts">
import { BrainstormingSidebar, type Board } from "@modules/ideation";
defineProps<{ board: Board; baseUrl: string }>();
</script>
<template><BrainstormingSidebar :board="board" :base-url="baseUrl" /></template>
