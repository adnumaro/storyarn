<script setup>
import { useLiveForm } from "live_vue";
import { Info } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { Separator } from "@components/ui/separator/index.js";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  passwordForm: { type: Object, required: true },
  currentEmail: { type: String, required: true },
  triggerSubmit: { type: Boolean, default: false },
  passwordAction: { type: String, required: true },
  translations: { type: Object, required: true },
});

const live = useLive();

const passwordForm = useLiveForm(() => props.passwordForm, {
  changeEvent: "validate_password",
  submitEvent: "update_password",
  debounceInMiliseconds: 300,
});

const password = passwordForm.field("password");
const passwordConfirmation = passwordForm.field("password_confirmation");

// For the form action POST, we use a hidden form that triggers on valid submit
const hiddenFormRef = ref(null);

// Watch for triggerSubmit from server
const checkTriggerSubmit = () => {
  if (props.triggerSubmit && hiddenFormRef.value) {
    hiddenFormRef.value.submit();
  }
};

// Use a watcher effect
import { watch } from "vue";

watch(
  () => props.triggerSubmit,
  (val) => {
    if (val && hiddenFormRef.value) {
      hiddenFormRef.value.submit();
    }
  },
);
</script>

<template>
  <div class="space-y-8">
    <!-- Hidden form for password action POST -->
    <form ref="hiddenFormRef" :action="passwordAction" method="post" class="hidden">
      <input
        type="hidden"
        name="_csrf_token"
        :value="document.querySelector('meta[name=csrf-token]')?.content"
      />
      <input type="hidden" name="_method" value="put" />
      <input
        :name="passwordForm.field('email')?.inputAttrs?.value?.name || 'user[email]'"
        type="hidden"
        autocomplete="username"
        :value="currentEmail"
      />
      <input
        :name="password.inputAttrs.value.name"
        type="hidden"
        :value="password.inputAttrs.value.value"
      />
      <input
        :name="passwordConfirmation.inputAttrs.value.name"
        type="hidden"
        :value="passwordConfirmation.inputAttrs.value.value"
      />
    </form>

    <!-- Password Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ translations.changePassword }}</h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ translations.passwordDescription }}
      </p>

      <div class="space-y-4">
        <input type="hidden" autocomplete="username" :value="currentEmail" />

        <div class="space-y-1.5">
          <Label for="security-password">{{ translations.newPassword }}</Label>
          <Input
            id="security-password"
            type="password"
            v-bind="password.inputAttrs.value"
            autocomplete="new-password"
            required
          />
          <p v-if="password.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ password.errorMessage.value }}
          </p>
        </div>

        <div class="space-y-1.5">
          <Label for="security-password-confirmation">{{ translations.confirmPassword }}</Label>
          <Input
            id="security-password-confirmation"
            type="password"
            v-bind="passwordConfirmation.inputAttrs.value"
            autocomplete="new-password"
          />
          <p v-if="passwordConfirmation.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ passwordConfirmation.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end gap-3">
          <Button @click="passwordForm.submit()">
            {{ translations.updatePassword }}
          </Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Sessions Section (future) -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ translations.activeSessions }}</h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ translations.sessionsDescription }}
      </p>
      <div
        class="flex items-center gap-2 rounded-md border border-border bg-muted/50 p-3 text-sm text-muted-foreground"
      >
        <Info class="size-5 shrink-0" />
        <span>{{ translations.sessionsComingSoon }}</span>
      </div>
    </section>
  </div>
</template>
