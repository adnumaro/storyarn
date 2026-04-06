<script setup lang="ts">
import { Shield } from "lucide-vue-next";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { useLive } from "@composables/useLive";

const { email, loginAction, backUrl = "/workspaces" } = defineProps<{
  email: string;
  loginAction: string;
  backUrl?: string;
}>();

const live = useLive();

function onSubmit() {
  live.pushEvent("submit_magic", { user: { email } });
}
</script>

<template>
  <div class="mx-auto max-w-sm space-y-6">
    <div class="text-center space-y-3">
      <div class="flex justify-center">
        <div class="rounded-full bg-yellow-500/10 p-3">
          <Shield class="size-8 text-yellow-500" />
        </div>
      </div>
      <div>
        <h1 class="text-2xl font-bold tracking-tight">Confirm access</h1>
        <p class="text-sm text-muted-foreground mt-2">
          This is a protected area. To continue, please verify your identity by requesting a new
          login link.
        </p>
      </div>
    </div>

    <form :action="loginAction" method="post" @submit.prevent="onSubmit">
      <div class="space-y-1.5 mb-4">
        <Label for="confirm-email">Email</Label>
        <Input
          id="confirm-email"
          :value="email"
          type="email"
          name="user[email]"
          autocomplete="email"
          readonly
          required
        />
      </div>
      <Button type="submit" class="w-full">
        Send verification link <span aria-hidden="true" class="ml-1">&rarr;</span>
      </Button>
    </form>

    <div class="text-center">
      <a
        :href="backUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        Go back
      </a>
    </div>
  </div>
</template>
