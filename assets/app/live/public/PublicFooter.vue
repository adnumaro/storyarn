<script setup lang="ts">
import { openCookiePreferences } from "@/js/utils/posthog";

const year = new Date().getFullYear();

function openCookieSettings(): void {
  openCookiePreferences();
}
</script>

<template>
  <footer class="landing-footer w-full border-t border-border/10 pb-8 pt-16 bg-[#111318]">
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <!-- Split Structure -->
      <div class="flex flex-col gap-12 sm:flex-row sm:justify-between mb-16">
        <!-- Left: Branding, Tagline, Badges -->
        <div class="flex flex-col items-start gap-5 max-w-104">
          <div class="flex items-center gap-3">
            <img
              :src="'/images/logos/logo-name-white.png'"
              alt="Storyarn"
              class="h-7 w-auto mix-blend-screen opacity-90"
            />
            <span
              class="rounded-full border border-border/20 bg-muted/30 px-3 py-1 text-[11px] font-semibold text-foreground/70 tracking-wide uppercase"
            >
              {{ $t("landing.common.badge") }}
            </span>
          </div>
          <p class="text-sm leading-relaxed text-muted-foreground/80">
            {{ $t("landing.footer.tagline") }}
          </p>
        </div>

        <!-- Right: Links Stack -->
        <nav class="flex flex-col gap-3 text-sm font-medium text-muted-foreground/80 pt-2 lg:mr-24">
          <a href="#features-section" class="transition-colors hover:text-foreground">{{
            $t("landing.common.links.features")
          }}</a>
          <a href="#discover" class="transition-colors hover:text-foreground">{{
            $t("landing.common.links.discover")
          }}</a>
          <a href="#workflow" class="transition-colors hover:text-foreground">{{
            $t("landing.common.links.workflow")
          }}</a>
          <a
            href="/docs"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="transition-colors hover:text-foreground"
            >{{ $t("landing.common.links.docs") }}</a
          >
          <a
            href="/blog"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="transition-colors hover:text-foreground"
            >{{ $t("landing.common.links.blog") }}</a
          >
          <a
            href="/contact"
            data-live-link-exempt="controller"
            class="transition-colors hover:text-foreground"
            >{{ $t("landing.common.links.contact") }}</a
          >
        </nav>
      </div>

      <!-- Bottom Edge -->
      <div
        class="flex flex-col gap-4 border-t border-border/10 pt-6 text-sm text-muted-foreground/50 sm:flex-row sm:items-center sm:justify-between"
      >
        <span>Storyarn &middot; {{ year }}</span>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <a
            href="/privacy"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="transition-colors hover:text-foreground"
          >
            {{ $t("public.layout.privacy") }}
          </a>
          <a
            href="/terms"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="transition-colors hover:text-foreground"
          >
            {{ $t("public.layout.terms") }}
          </a>
          <a
            href="/privacy#cookies"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="transition-colors hover:text-foreground"
          >
            {{ $t("public.layout.cookies") }}
          </a>
          <button
            type="button"
            class="transition-colors hover:text-foreground"
            @click="openCookieSettings"
          >
            {{ $t("public.layout.manage_cookies") }}
          </button>
        </div>
      </div>
    </div>
  </footer>
</template>
