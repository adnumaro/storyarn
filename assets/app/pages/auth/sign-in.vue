<script setup>
import { Info } from "lucide-vue-next";
import { onMounted, ref } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  email: { type: String, default: "" },
  readonly: { type: Boolean, default: false },
  localMailAdapter: { type: Boolean, default: false },
  loginAction: { type: String, required: true },
});

const live = useLive();
const emailValue = ref(props.email || "");
const emailInput = ref(null);

onMounted(() => {
  emailInput.value?.focus();
});

function onSubmit() {
  live.pushEvent("submit_magic", { user: { email: emailValue.value } });
}
</script>

<template>
  <div class="mx-auto max-w-sm space-y-4">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">Log in</h1>
      <p class="text-sm text-muted-foreground">Enter your email and we'll send you a login link.</p>
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

    <form :action="loginAction" method="post" @submit.prevent="onSubmit">
      <div class="space-y-1.5 mb-4">
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
      <Button type="submit" class="w-full">
        Log in with email <span aria-hidden="true" class="ml-1">&rarr;</span>
      </Button>
    </form>
  </div>
</template>
