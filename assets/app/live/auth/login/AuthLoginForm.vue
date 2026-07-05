<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { ArrowRight, Info } from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";

interface LoginFormValues {
  email: string;
  password: string;
}

type LoginForm = Form<LoginFormValues> & { action?: string };

const {
  form: formProp,
  readonly = false,
  triggerSubmit = false,
  loginToken = null,
  localMailAdapter = false,
  csrfToken,
  loginAction,
} = defineProps<{
  form: LoginForm;
  readonly?: boolean;
  triggerSubmit?: boolean;
  loginToken?: string | null;
  localMailAdapter?: boolean;
  csrfToken: string;
  loginAction: string;
}>();

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "log_in",
  debounceInMiliseconds: 300,
});

const email = form.field("email");
const password = form.field("password");

const emailValue = computed({
  get: () => String(email.value.value || ""),
  set: (value: string) => {
    email.value.value = value;
  },
});

const passwordValue = computed({
  get: () => String(password.value.value || ""),
  set: (value: string) => {
    password.value.value = value;
  },
});

const showEmailError = computed(
  () =>
    Boolean(email.errorMessage.value) &&
    (formProp.action === "insert" || email.isDirty.value || email.isTouched.value),
);

const showPasswordError = computed(
  () =>
    Boolean(password.errorMessage.value) &&
    (formProp.action === "insert" || password.isDirty.value || password.isTouched.value),
);

const emailInputAttrs = computed(() => {
  const {
    value: _value,
    onInput: _onInput,
    "aria-invalid": _ariaInvalid,
    "aria-describedby": ariaDescribedBy,
    ...attrs
  } = email.inputAttrs.value;

  return {
    ...attrs,
    "aria-invalid": showEmailError.value ? true : undefined,
    "aria-describedby": showEmailError.value ? ariaDescribedBy : undefined,
  };
});

const passwordInputAttrs = computed(() => {
  const {
    value: _value,
    onInput: _onInput,
    "aria-invalid": _ariaInvalid,
    "aria-describedby": ariaDescribedBy,
    ...attrs
  } = password.inputAttrs.value;

  return {
    ...attrs,
    "aria-invalid": showPasswordError.value ? true : undefined,
    "aria-describedby": showPasswordError.value ? ariaDescribedBy : undefined,
  };
});

function updateEmail(value: string | number): void {
  emailValue.value = String(value);
}

function updatePassword(value: string | number): void {
  passwordValue.value = String(value);
}

const hiddenFormRef = ref<HTMLFormElement | null>(null);
const emailInput = ref<InstanceType<typeof Input> | null>(null);

watch(
  () => triggerSubmit,
  (value) => {
    if (value && loginToken && hiddenFormRef.value) {
      hiddenFormRef.value.submit();
    }
  },
);

onMounted(() => {
  emailInput.value?.focus();
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
              <a
                href="/dev/mailbox"
                data-live-link-exempt="dev-controller"
                class="underline hover:text-foreground"
              >
                {{ $t("auth.sign_in.mailbox_link") }}
              </a>
            </template>
          </i18n-t>
        </p>
      </div>
    </div>

    <form ref="hiddenFormRef" :action="loginAction" method="post" class="hidden">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
      <input type="hidden" name="user[_login_token]" :value="loginToken || ''" />
    </form>

    <form id="login-form" novalidate @submit.prevent="form.submit()">
      <div class="space-y-4 mb-6">
        <div class="space-y-1.5">
          <Label for="login-email">{{ $t("auth.email") }}</Label>
          <Input
            v-bind="emailInputAttrs"
            id="login-email"
            ref="emailInput"
            :model-value="emailValue"
            type="email"
            name="user[email]"
            autocomplete="email"
            :readonly="readonly"
            required
            @update:model-value="updateEmail"
          />
          <p
            v-if="showEmailError"
            id="email-error"
            role="alert"
            class="text-sm font-medium text-destructive"
          >
            {{ email.errorMessage.value }}
          </p>
        </div>
        <div class="space-y-1.5">
          <Label for="login-password">{{ $t("auth.password") }}</Label>
          <Input
            v-bind="passwordInputAttrs"
            id="login-password"
            :model-value="passwordValue"
            type="password"
            name="user[password]"
            autocomplete="current-password"
            required
            @update:model-value="updatePassword"
          />
          <p
            v-if="showPasswordError"
            id="password-error"
            role="alert"
            class="text-sm font-medium text-destructive"
          >
            {{ password.errorMessage.value }}
          </p>
        </div>
      </div>
      <Button type="submit" class="w-full">
        {{ $t("auth.sign_in.submit") }} <ArrowRight class="ml-1" />
      </Button>
    </form>
  </div>
</template>
