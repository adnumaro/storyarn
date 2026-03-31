<script setup>
import { useLiveForm } from "live_vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.js";
import { Separator } from "@components/ui/separator/index.js";

const props = defineProps({
  profileForm: { type: Object, required: true },
  emailForm: { type: Object, required: true },
  currentEmail: { type: String, required: true },
  translations: { type: Object, required: true },
});

const profileForm = useLiveForm(() => props.profileForm, {
  changeEvent: "validate_profile",
  submitEvent: "update_profile",
  debounceInMiliseconds: 300,
});

const emailForm = useLiveForm(() => props.emailForm, {
  changeEvent: "validate_email",
  submitEvent: "update_email",
  debounceInMiliseconds: 300,
});

const displayName = profileForm.field("display_name");
const locale = profileForm.field("locale");
const email = emailForm.field("email");
</script>

<template>
  <div class="space-y-8">
    <!-- Profile Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ translations.personalInfo }}</h3>

      <div class="space-y-4">
        <div class="space-y-1.5">
          <Label for="profile-display-name">{{ translations.displayName }}</Label>
          <Input
            id="profile-display-name"
            v-bind="displayName.inputAttrs.value"
            :placeholder="translations.displayNamePlaceholder"
          />
          <p v-if="displayName.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ displayName.errorMessage.value }}
          </p>
        </div>

        <div class="space-y-1.5">
          <Label for="profile-locale">{{ translations.language }}</Label>
          <Select
            :model-value="locale.inputAttrs.value.value || ''"
            @update:model-value="
              (val) =>
                locale.inputAttrs.value['onUpdate:modelValue']?.(val) ??
                locale.inputAttrs.value.onInput?.({ target: { value: val } })
            "
          >
            <SelectTrigger id="profile-locale" class="w-full">
              <SelectValue :placeholder="translations.autoDetect" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">{{ translations.autoDetect }}</SelectItem>
              <SelectItem value="en">English</SelectItem>
              <SelectItem value="es">Espa&#241;ol</SelectItem>
            </SelectContent>
          </Select>
          <p v-if="locale.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ locale.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end gap-3">
          <Button @click="profileForm.submit()">
            {{ translations.saveProfile }}
          </Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Email Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ translations.emailAddress }}</h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ translations.emailDescription }}
      </p>

      <div class="space-y-4">
        <div class="space-y-1.5">
          <Label for="profile-email">{{ translations.email }}</Label>
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
          <Button @click="emailForm.submit()">
            {{ translations.changeEmail }}
          </Button>
        </div>
      </div>
    </section>
  </div>
</template>
