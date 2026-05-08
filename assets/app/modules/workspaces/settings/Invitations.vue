<script setup lang="ts">
import { XCircle } from "lucide-vue-next";
import { Button } from "@components/ui/button";

const { homepageUrl = "/" } = defineProps<{
  homepageUrl?: string;
}>();
</script>

<template>
  <div class="max-w-lg mx-auto text-center py-12 space-y-6">
    <XCircle class="size-16 mx-auto text-destructive" />
    <div>
      <h1 class="text-2xl font-bold tracking-tight">
        {{ $t("workspace.invitation.invalid_title") }}
      </h1>
      <p class="text-sm text-muted-foreground mt-2">
        {{ $t("workspace.invitation.invalid_description") }}
      </p>
    </div>
    <a :href="homepageUrl" data-phx-link="redirect" data-phx-link-state="push">
      <Button>{{ $t("workspace.invitation.go_home") }}</Button>
    </a>
  </div>
</template>
