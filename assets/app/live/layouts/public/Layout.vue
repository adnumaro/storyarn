<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { BookOpen, Mail, Menu, PanelsTopLeft, Sparkles, X } from "lucide-vue-next";
import LiveLink from "@components/navigation/LiveLink.vue";

interface PublicLayoutUrls {
  home: string;
  docs: string;
  contact: string;
  login: string;
  workspaces: string;
}

const {
  isLoggedIn = false,
  theme = null,
  urls,
} = defineProps<{
  isLoggedIn?: boolean;
  theme?: string | null;
  urls: PublicLayoutUrls;
}>();

const { t } = useI18n();
const mobileOpen = ref(false);
const isDark = computed(() => theme === "dark");

const headerClass = computed(() => [
  "w-[min(calc(100%-48px),1280px)] h-16 flex items-center",
  isDark.value &&
    "z-[120] rounded-full border border-border bg-background/70 px-5 backdrop-blur-xl shadow-[0_20px_80px_rgba(0,0,0,0.28)]",
]);

const headerStyle = computed(() =>
  isDark.value
    ? {
        position: "fixed",
        top: "1.25rem",
        left: "50%",
        transform: "translateX(-50%)",
      }
    : undefined,
);

function closeMobileNav(): void {
  mobileOpen.value = false;
}

function openMobileNav(): void {
  mobileOpen.value = true;
}

function scrollToPanel(panelIndex: number): void {
  window.dispatchEvent(new CustomEvent("storyarn:force-scroll", { detail: { panelIndex } }));
  closeMobileNav();
}
</script>

<template>
  <div
    :class="['min-h-screen flex flex-col w-full bg-background text-foreground', isDark && 'dark']"
  >
    <header :class="headerClass" :style="headerStyle">
      <div class="flex w-full items-center gap-4 px-4 sm:px-5 lg:px-6">
        <div class="flex-none">
          <LiveLink :to="urls.home" class="flex items-center">
            <img
              :src="'/images/logos/logo-name-black.png'"
              alt="Storyarn"
              class="h-[42px] w-auto dark:hidden"
            />
            <img
              :src="'/images/logos/logo-name-white.png'"
              alt="Storyarn"
              class="hidden h-[42px] w-auto dark:block"
            />
          </LiveLink>
        </div>

        <div class="hidden min-w-0 flex-1 items-center justify-between gap-6 xl:flex">
          <nav class="flex min-w-0 items-center gap-2">
            <a
              href="#features"
              class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
              @click.prevent="scrollToPanel(1)"
            >
              {{ t("landing.common.links.features") }}
            </a>
            <a
              href="#discover"
              class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
              @click.prevent="scrollToPanel(2)"
            >
              {{ t("landing.common.links.discover") }}
            </a>
            <LiveLink
              :to="urls.docs"
              class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
            >
              {{ t("landing.common.links.docs") }}
            </LiveLink>
            <LiveLink
              :to="urls.contact"
              class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
            >
              {{ t("landing.common.links.contact") }}
            </LiveLink>
          </nav>

          <div class="flex flex-none items-center gap-2">
            <LiveLink
              v-if="isLoggedIn"
              :to="urls.workspaces"
              class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
            >
              {{ t("public.layout.dashboard") }}
            </LiveLink>
            <template v-else>
              <a
                href="#waitlist"
                class="inline-flex items-center justify-center rounded-md px-5 py-2.5 text-sm font-bold text-teal-950 transition-all hover:scale-105"
                style="
                  background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210));
                  box-shadow:
                    0 0 20px rgba(34, 211, 238, 0.4),
                    inset 0 1px 0 rgba(255, 255, 255, 0.3);
                "
                @click.prevent="scrollToPanel(3)"
              >
                {{ t("public.layout.request_access") }}
              </a>
              <LiveLink
                :to="urls.login"
                class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
              >
                {{ t("public.layout.log_in") }}
              </LiveLink>
            </template>
          </div>
        </div>

        <div class="ml-auto flex-none xl:hidden">
          <button
            type="button"
            class="inline-flex size-8 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
            :aria-label="t('public.layout.menu')"
            @click="openMobileNav"
          >
            <Menu class="size-5" />
          </button>
        </div>
      </div>
    </header>

    <nav
      v-show="mobileOpen"
      id="mobile-nav"
      :class="[
        'fixed inset-0 z-[140] w-screen max-w-none xl:hidden',
        isDark && 'bg-background/96 backdrop-blur-xl',
      ]"
    >
      <div class="flex min-h-screen">
        <aside class="flex min-h-screen w-full justify-center bg-background/98 px-5 pb-8 pt-5">
          <div class="flex min-h-full w-full max-w-[420px] flex-col">
            <div class="flex items-center justify-between gap-4">
              <LiveLink :to="urls.home" class="flex items-center text-foreground">
                <img
                  :src="'/images/logos/logo-name-black.png'"
                  alt="Storyarn"
                  class="h-[42px] w-auto dark:hidden"
                />
                <img
                  :src="'/images/logos/logo-name-white.png'"
                  alt="Storyarn"
                  class="hidden h-[42px] w-auto dark:block"
                />
              </LiveLink>
              <button
                type="button"
                class="inline-flex size-8 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                :aria-label="t('public.layout.close')"
                @click="closeMobileNav"
              >
                <X class="size-5" />
              </button>
            </div>

            <div class="mt-8 grid gap-2">
              <a
                href="#features"
                class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                @click.prevent="scrollToPanel(1)"
              >
                <Sparkles class="size-5 text-foreground/45" />
                {{ t("landing.common.links.features") }}
              </a>
              <a
                href="#discover"
                class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                @click.prevent="scrollToPanel(2)"
              >
                <PanelsTopLeft class="size-5 text-foreground/45" />
                {{ t("landing.common.links.discover") }}
              </a>
              <LiveLink
                :to="urls.docs"
                class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                @click="closeMobileNav"
              >
                <BookOpen class="size-5 text-foreground/45" />
                {{ t("landing.common.links.docs") }}
              </LiveLink>
              <LiveLink
                :to="urls.contact"
                class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                @click="closeMobileNav"
              >
                <Mail class="size-5 text-foreground/45" />
                {{ t("landing.common.links.contact") }}
              </LiveLink>
            </div>

            <div class="mt-auto grid gap-3 border-t border-border pt-5">
              <LiveLink
                v-if="isLoggedIn"
                :to="urls.workspaces"
                class="btn-block inline-flex items-center justify-center rounded-2xl bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
                @click="closeMobileNav"
              >
                {{ t("public.layout.dashboard") }}
              </LiveLink>
              <template v-else>
                <a
                  href="#waitlist"
                  class="inline-flex w-full items-center justify-center rounded-xl px-4 py-2.5 text-sm font-bold text-teal-950 transition-all hover:scale-105"
                  style="
                    background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210));
                    box-shadow:
                      0 0 20px rgba(34, 211, 238, 0.4),
                      inset 0 1px 0 rgba(255, 255, 255, 0.3);
                  "
                  @click.prevent="scrollToPanel(3)"
                >
                  {{ t("public.layout.request_access") }}
                </a>
                <LiveLink
                  :to="urls.login"
                  class="btn-block inline-flex items-center justify-center rounded-2xl px-3 py-2 text-sm transition-colors hover:bg-accent"
                  @click="closeMobileNav"
                >
                  {{ t("public.layout.log_in") }}
                </LiveLink>
              </template>
            </div>
          </div>
        </aside>
      </div>
    </nav>

    <main class="flex flex-1 flex-col">
      <slot />
    </main>
  </div>
</template>
