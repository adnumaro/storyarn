<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { BarChart3, Cookie, ShieldCheck } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import { Switch } from "@components/ui/switch";
import {
  initPostHog,
  postHogConsentRequired,
  readCookieConsent,
  saveCookieConsent,
} from "@/js/utils/posthog";

const { privacyUrl = "/privacy#cookies", termsUrl = "/terms" } = defineProps<{
  privacyUrl?: string;
  termsUrl?: string;
}>();

const { t } = useI18n();
const consent = ref<ReturnType<typeof readCookieConsent>>(null);
const settingsOpen = ref(false);
const analyticsEnabled = ref(false);
const analyticsAvailable = ref(false);

const bannerOpen = computed(
  () => analyticsAvailable.value && !consent.value && !settingsOpen.value,
);

function syncConsent(): void {
  analyticsAvailable.value = postHogConsentRequired();
  consent.value = readCookieConsent();
  analyticsEnabled.value = consent.value?.analytics === true;
}

function acceptAnalytics(): void {
  saveCookieConsent({ analytics: true });
  settingsOpen.value = false;
  syncConsent();
}

function rejectAnalytics(): void {
  saveCookieConsent({ analytics: false });
  settingsOpen.value = false;
  syncConsent();
}

function savePreferences(): void {
  saveCookieConsent({ analytics: analyticsEnabled.value });
  settingsOpen.value = false;
  syncConsent();
}

function openSettings(): void {
  syncConsent();
  settingsOpen.value = true;
}

function handleOpenSettings(): void {
  openSettings();
}

function handleConsentUpdated(): void {
  syncConsent();
}

function closeSettings(): void {
  settingsOpen.value = false;
}

onMounted(() => {
  syncConsent();
  initPostHog();
  window.addEventListener("storyarn:open-cookie-settings", handleOpenSettings);
  window.addEventListener("storyarn:cookie-consent-updated", handleConsentUpdated);
});

onUnmounted(() => {
  window.removeEventListener("storyarn:open-cookie-settings", handleOpenSettings);
  window.removeEventListener("storyarn:cookie-consent-updated", handleConsentUpdated);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="bannerOpen"
      class="fixed inset-x-0 bottom-0 z-200 border-t border-border bg-background/97 px-4 py-4 text-foreground shadow-[0_-20px_80px_rgba(0,0,0,0.32)] backdrop-blur-xl"
      role="region"
      :aria-label="t('public.cookies.banner_aria')"
    >
      <div
        class="mx-auto flex w-[min(calc(100%-16px),1120px)] flex-col gap-4 lg:flex-row lg:items-center lg:justify-between"
      >
        <div class="flex min-w-0 gap-3">
          <div
            class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-md border border-primary/20 bg-primary/10 text-primary"
            aria-hidden="true"
          >
            <Cookie class="size-4" />
          </div>
          <div class="min-w-0">
            <h2 class="text-sm font-semibold">{{ t("public.cookies.banner_title") }}</h2>
            <p class="mt-1 max-w-3xl text-sm leading-6 text-muted-foreground">
              {{ t("public.cookies.banner_description") }}
              <a
                :href="privacyUrl"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="font-medium text-primary underline-offset-4 hover:underline"
              >
                {{ t("public.cookies.learn_more") }}
              </a>
            </p>
          </div>
        </div>

        <div class="flex flex-col gap-2 sm:flex-row sm:justify-end lg:shrink-0">
          <Button variant="secondary" class="sm:min-w-36" @click="rejectAnalytics">
            {{ t("public.cookies.reject") }}
          </Button>
          <Button variant="outline" class="sm:min-w-36" @click="openSettings">
            {{ t("public.cookies.configure") }}
          </Button>
          <Button class="sm:min-w-36" @click="acceptAnalytics">
            {{ t("public.cookies.accept") }}
          </Button>
        </div>
      </div>
    </div>

    <div
      v-if="settingsOpen"
      class="fixed inset-0 z-210 flex items-end justify-center bg-background/70 px-4 py-5 backdrop-blur-sm sm:items-center"
      role="dialog"
      aria-modal="true"
      :aria-label="t('public.cookies.settings_title')"
      @click.self="closeSettings"
    >
      <section
        class="w-full max-w-lg rounded-lg border border-border bg-card p-5 text-card-foreground shadow-2xl"
      >
        <div class="flex items-start gap-3">
          <div
            class="flex size-9 shrink-0 items-center justify-center rounded-md border border-primary/20 bg-primary/10 text-primary"
            aria-hidden="true"
          >
            <ShieldCheck class="size-4" />
          </div>
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">{{ t("public.cookies.settings_title") }}</h2>
            <p class="mt-1 text-sm leading-6 text-muted-foreground">
              {{ t("public.cookies.settings_description") }}
            </p>
          </div>
        </div>

        <div class="mt-5 grid gap-3">
          <div class="rounded-md border border-border bg-muted/25 p-4">
            <div class="flex items-center justify-between gap-4">
              <div>
                <h3 class="text-sm font-semibold">{{ t("public.cookies.required_title") }}</h3>
                <p class="mt-1 text-sm leading-5 text-muted-foreground">
                  {{ t("public.cookies.required_description") }}
                </p>
              </div>
              <Switch :model-value="true" disabled />
            </div>
          </div>

          <div class="rounded-md border border-border bg-muted/25 p-4">
            <div class="flex items-center justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <BarChart3 class="size-4 text-primary" aria-hidden="true" />
                  <h3 class="text-sm font-semibold">{{ t("public.cookies.analytics_title") }}</h3>
                </div>
                <p class="mt-1 text-sm leading-5 text-muted-foreground">
                  {{ t("public.cookies.analytics_description") }}
                </p>
              </div>
              <Switch
                v-model="analyticsEnabled"
                :disabled="!analyticsAvailable"
                :aria-label="t('public.cookies.analytics_title')"
              />
            </div>
          </div>
        </div>

        <div
          class="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-between"
        >
          <a
            :href="termsUrl"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
          >
            {{ t("public.cookies.terms_link") }}
          </a>
          <div class="flex flex-col gap-2 sm:flex-row">
            <Button variant="secondary" @click="rejectAnalytics">
              {{ t("public.cookies.reject") }}
            </Button>
            <Button @click="savePreferences">
              {{ t("public.cookies.save") }}
            </Button>
          </div>
        </div>
      </section>
    </div>
  </Teleport>
</template>
