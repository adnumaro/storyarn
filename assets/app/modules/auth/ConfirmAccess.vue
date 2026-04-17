<script setup lang="ts">
import { ArrowRight, Shield } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";

const {
  email,
  loginAction,
  backUrl = "/workspaces",
  csrfToken,
} = defineProps<{
  email: string;
  loginAction: string;
  backUrl?: string;
  csrfToken: string;
}>();

const passwordValue = ref("");
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
        <h1 class="text-2xl font-bold tracking-tight">
          {{ $t("auth.confirm_access.title") }}
        </h1>
        <p class="text-sm text-muted-foreground mt-2">
          {{ $t("auth.confirm_access.subtitle") }}
        </p>
      </div>
    </div>

    <form :action="loginAction" method="post">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
      <div class="space-y-1.5 mb-4">
        <Label for="confirm-email">{{ $t("auth.email") }}</Label>
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
      <div class="space-y-1.5 mb-4">
        <Label for="confirm-password">{{ $t("auth.password") }}</Label>
        <Input
          id="confirm-password"
          v-model="passwordValue"
          type="password"
          name="user[password]"
          autocomplete="current-password"
          required
          autofocus
        />
      </div>
      <Button type="submit" class="w-full">
        {{ $t("auth.confirm_access.submit") }} <ArrowRight class="ml-1" />
      </Button>
    </form>

    <div class="text-center">
      <a
        :href="backUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        {{ $t("auth.confirm_access.go_back") }}
      </a>
    </div>
  </div>
</template>
