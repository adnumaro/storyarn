<script setup lang="ts">
import AssetUploadButton from "@components/forms/assets/AssetUploadButton.vue";

const { uploading = false } = defineProps<{
  uploading?: boolean;
}>();
</script>

<template>
  <AssetUploadButton :uploading="uploading" />
</template>
