<script setup lang="ts">
import { computed } from "vue";
import { ArrowUpRight, Mail, MessageCircle } from "lucide-vue-next";

const { contactEmail } = defineProps<{
  contactEmail: string;
}>();

const contactHref = computed(() => `mailto:${contactEmail}`);
</script>

<template>
  <div class="flex min-h-full flex-1 flex-col">
    <section class="mx-auto w-full max-w-7xl px-6 py-24 sm:py-36">
      <div class="max-w-lg">
        <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">
          {{ $t("public.contact.title") }}
        </h1>
        <p class="mt-4 text-lg leading-relaxed text-muted-foreground">
          {{ $t("public.contact.description") }}
        </p>
      </div>

      <div class="mt-12 grid max-w-2xl gap-8 sm:grid-cols-2">
        <article class="rounded-xl border border-border/50 bg-muted/30 p-6">
          <div
            class="mb-4 flex size-11 items-center justify-center rounded-xl bg-primary/10 text-primary"
          >
            <Mail class="size-5" />
          </div>
          <h2 class="text-lg font-semibold">{{ $t("public.contact.email.title") }}</h2>
          <p class="mt-2 leading-relaxed text-muted-foreground">
            {{ $t("public.contact.email.description") }}
          </p>
          <a
            :href="contactHref"
            data-live-link-exempt="mailto"
            class="mt-4 inline-flex items-center gap-1 text-primary hover:underline"
          >
            {{ contactEmail }}
            <ArrowUpRight class="size-4" />
          </a>
        </article>

        <article class="rounded-xl border border-border/50 bg-muted/30 p-6">
          <div
            class="mb-4 flex size-11 items-center justify-center rounded-xl bg-accent/10 text-accent"
          >
            <MessageCircle class="size-5" />
          </div>
          <h2 class="text-lg font-semibold">{{ $t("public.contact.discord.title") }}</h2>
          <p class="mt-2 leading-relaxed text-muted-foreground">
            {{ $t("public.contact.discord.description") }}
          </p>
          <a
            href="https://discord.gg/storyarn"
            class="mt-4 inline-flex items-center gap-1 text-primary hover:underline"
            target="_blank"
            rel="noopener"
          >
            {{ $t("public.contact.discord.link") }}
            <ArrowUpRight class="size-4" />
          </a>
        </article>
      </div>
    </section>
  </div>
</template>
