<script setup lang="ts">
import InvitationResponse from "@components/invitations/InvitationResponse.vue";

const { homepageUrl = "/" } = defineProps<{
  homepageUrl?: string;
}>();
</script>

<template>
  <InvitationResponse :homepage-url="homepageUrl" />
</template>
