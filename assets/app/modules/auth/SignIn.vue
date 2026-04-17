<script setup lang="ts">
import { Info } from "lucide-vue-next";
import { onMounted, ref } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { ArrowRight } from "lucide-vue-next";

const {
  email = "",
  readonly = false,
  localMailAdapter = false,
  loginAction,
  csrfToken,
} = defineProps<{
  email?: string;
  readonly?: boolean;
  localMailAdapter?: boolean;
  csrfToken: string;
  loginAction: string;
}>();

const emailValue = ref(email || "");
const passwordValue = ref("");
const emailInput = ref<InstanceType<typeof Input> | null>(null);

onMounted(() => {
  (emailInput.value?.$el as HTMLInputElement)?.focus();
});
</script>

<template>
  <div class="mx-auto max-w-sm space-y-4">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">
        {{ $t("auth.sign_in.title") }}
      </h1>
      <p class="text-sm text-muted-foreground">
        {{ $t("auth.sign_in.subtitle") }}
      </p>
    </div>

    <div
      v-if="localMailAdapter"
      class="rounded-lg border border-border bg-blue-500/10 p-3 flex items-start gap-3 text-sm"
    >
      <Info class="size-5 shrink-0 text-blue-500 mt-0.5" />
      <div>
        <p>{{ $t("auth.sign_in.local_mail_notice") }}</p>
        <p>
          <i18n-t keypath="auth.sign_in.local_mail_link" tag="span">
            <template #link>
              <a href="/dev/mailbox" class="underline hover:text-foreground">
                {{ $t("auth.sign_in.mailbox_link") }}
              </a>
            </template>
          </i18n-t>
        </p>
      </div>
    </div>

    <form :action="loginAction" method="post">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
      <div class="space-y-4 mb-6">
        <div class="space-y-1.5">
          <Label for="login-email">{{ $t("auth.email") }}</Label>
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
          <Label for="login-password">{{ $t("auth.password") }}</Label>
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
        {{ $t("auth.sign_in.submit") }} <ArrowRight class="ml-1" />
      </Button>
    </form>
  </div>
</template>
