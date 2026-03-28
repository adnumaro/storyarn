<script setup>
import { XCircle } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";

defineProps({
	homepageUrl: { type: String, default: "/" },
});
</script>

<template>
  <div class="max-w-lg mx-auto text-center py-12 space-y-6">
    <XCircle class="size-16 mx-auto text-destructive" />
    <div>
      <h1 class="text-2xl font-bold tracking-tight">Invalid Invitation</h1>
      <p class="text-sm text-muted-foreground mt-2">
        This invitation link is invalid or has expired.
      </p>
    </div>
    <a :href="homepageUrl" data-phx-link="redirect" data-phx-link-state="push">
      <Button>Go to Homepage</Button>
    </a>
  </div>
</template>
