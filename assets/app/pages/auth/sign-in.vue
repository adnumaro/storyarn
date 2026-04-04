<script setup>
import { Info } from "lucide-vue-next";
import { onMounted, ref } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { useLive } from "@composables/useLive.js";

const { email, readonly, localMailAdapter, loginAction } = defineProps({
  email: { type: String, default: "" },
  readonly: { type: Boolean, default: false },
  localMailAdapter: { type: Boolean, default: false },
  loginAction: { type: String, required: true },
});

const emailValue = ref(email || "");
const passwordValue = ref("");
const csrfToken = ref("");
const emailInput = ref(null);

onMounted(() => {
  emailInput.value?.focus();
  csrfToken.value = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || "";
});
</script>

<template>
  <div class="mx-auto max-w-sm space-y-4">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">Log in</h1>
      <p class="text-sm text-muted-foreground">Enter your email and password to access your account.</p>
    </div>

    <div
      v-if="localMailAdapter"
      class="rounded-lg border border-border bg-blue-500/10 p-3 flex items-start gap-3 text-sm"
    >
      <Info class="size-5 shrink-0 text-blue-500 mt-0.5" />
      <div>
        <p>You are running the local mail adapter.</p>
        <p>
          To see sent emails, visit
          <a href="/dev/mailbox" class="underline hover:text-foreground">the mailbox sheet</a>.
        </p>
      </div>
    </div>

    <form :action="loginAction" method="post">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
      <div class="space-y-4 mb-6">
        <div class="space-y-1.5">
          <Label for="login-email">Email</Label>
          <Input
            id="login-email"
            ref="emailInput"
            v-model="emailValue"
            type="email"
            name="user[email]"
            autocomplete="email"
            :readonly="readonly"
            required
          />
        </div>
        <div class="space-y-1.5">
          <Label for="login-password">Password</Label>
          <Input
            id="login-password"
            v-model="passwordValue"
            type="password"
            name="user[password]"
            autocomplete="current-password"
            required
          />
        </div>
      </div>
      <Button type="submit" class="w-full">
        Log in <span aria-hidden="true" class="ml-1">&rarr;</span>
      </Button>
    </form>
  </div>
</template>
