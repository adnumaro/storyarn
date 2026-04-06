<script setup>
import { useLiveForm } from "live_vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.ts";
import { Separator } from "@components/ui/separator/index.ts";

const {
  profileForm: profileFormProp,
  emailForm: emailFormProp,
  currentEmail,
} = defineProps({
  profileForm: { type: Object, required: true },
  emailForm: { type: Object, required: true },
  currentEmail: { type: String, required: true },
});

const profileForm = useLiveForm(() => profileFormProp, {
  changeEvent: "validate_profile",
  submitEvent: "update_profile",
  debounceInMilliseconds: 300,
});

const emailForm = useLiveForm(() => emailFormProp, {
  changeEvent: "validate_email",
  submitEvent: "update_email",
  debounceInMilliseconds: 300,
});

const displayName = profileForm.field("display_name");
const locale = profileForm.field("locale");
const email = emailForm.field("email");
</script>

<template>
  <div class="space-y-8">
    <div class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.profile.title") }}
      </h1>
      <p class="text-base text-muted-foreground">
        {{ $t("settings.profile.subtitle") }}
      </p>
    </div>

    <!-- Profile Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("settings.profile.personal_info") }}</h3>

      <div class="space-y-4">
        <div class="space-y-1.5">
          <Label for="profile-display-name">{{ $t("settings.profile.display_name") }}</Label>
          <Input
            id="profile-display-name"
            v-bind="displayName.inputAttrs.value"
            :placeholder="$t('settings.profile.display_name_placeholder')"
          />
          <p v-if="displayName.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ displayName.errorMessage.value }}
          </p>
        </div>

        <div class="space-y-1.5">
          <Label for="profile-locale">{{ $t("settings.profile.language") }}</Label>
          <Select
            :model-value="locale.inputAttrs.value.value || ''"
            @update:model-value="
              (val) =>
                locale.inputAttrs.value['onUpdate:modelValue']?.(val) ??
                locale.inputAttrs.value.onInput?.({ target: { value: val } })
            "
          >
            <SelectTrigger id="profile-locale" class="w-full">
              <SelectValue :placeholder="$t('settings.profile.auto_detect')" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">{{ $t("settings.profile.auto_detect") }}</SelectItem>
              <SelectItem value="en">English</SelectItem>
              <SelectItem value="es">Espa&#241;ol</SelectItem>
            </SelectContent>
          </Select>
          <p v-if="locale.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ locale.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end gap-3">
          <Button @click="profileForm.submit()"> {{ $t("settings.profile.save_profile") }} </Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Email Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("settings.profile.email_address") }}</h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ $t("settings.profile.email_description") }}
      </p>

      <div class="space-y-4">
        <div class="space-y-1.5">
          <Label for="profile-email">{{ $t("settings.profile.email") }}</Label>
          <Input
            id="profile-email"
            type="email"
            v-bind="email.inputAttrs.value"
            autocomplete="username"
            required
          />
          <p v-if="email.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ email.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end gap-3">
          <Button @click="emailForm.submit()"> {{ $t("settings.profile.change_email") }} </Button>
        </div>
      </div>
    </section>
  </div>
</template>
