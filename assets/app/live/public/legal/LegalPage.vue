<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Cookie, FileText, ShieldCheck, SlidersHorizontal } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import LandingFooter from "../PublicFooter.vue";

const {
  contactEmail,
  controllerAddress,
  controllerName,
  document: legalDocument,
  updatedAt,
} = defineProps<{
  contactEmail: string;
  controllerAddress: string;
  controllerName: string;
  document: "privacy" | "terms";
  updatedAt: string;
}>();

const { t } = useI18n();

const isPrivacy = computed(() => legalDocument === "privacy");
const documentBase = computed(() => `public.legal.${legalDocument}`);
const contactHref = computed(() => `mailto:${contactEmail}`);

const privacyDataItems = ["waitlist", "account", "projects", "technical", "analytics"];
const privacyPurposeItems = ["access", "service", "security", "improvement", "communications"];
const cookieRows = ["session", "remember", "theme", "consent", "posthog"];
const providerRows = ["fly", "neon", "tigris", "resend", "posthog", "sentry"];
const acceptableUseItems = ["illegal", "malware", "unauthorized_access", "unrelated", "limits", "minor_safety"];

function docText(key: string, params = {}): string {
  return t(`${documentBase.value}.${key}`, params);
}

function legalText(key: string, params = {}): string {
  return t(`public.legal.${key}`, params);
}

function openCookieSettings(): void {
  window.dispatchEvent(new CustomEvent("storyarn:open-cookie-settings"));
}
</script>

<template>
  <div class="min-h-screen bg-background pt-28 text-foreground">
    <main class="mx-auto w-[min(calc(100%-48px),960px)] pb-24">
      <section class="border-b border-border pb-10">
        <div
          class="mb-5 inline-flex items-center gap-2 rounded-md border border-primary/25 bg-primary/10 px-3 py-1.5 text-xs font-semibold uppercase text-primary"
        >
          <ShieldCheck v-if="isPrivacy" class="size-3.5" />
          <FileText v-else class="size-3.5" />
          {{ docText("eyebrow") }}
        </div>
        <h1 class="max-w-4xl text-4xl font-bold leading-tight sm:text-5xl">
          {{ docText("title") }}
        </h1>
        <p class="mt-5 max-w-3xl text-base leading-8 text-muted-foreground">
          {{ docText("description") }}
        </p>
        <p class="mt-4 text-sm text-muted-foreground">
          {{ legalText("last_updated", { date: updatedAt }) }}
        </p>
      </section>

      <article v-if="isPrivacy" class="legal-document space-y-12 py-12">
        <section class="space-y-4">
          <h2>{{ docText("controller.title") }}</h2>
          <p>
            {{
              docText("controller.identity", {
                controllerAddress,
                controllerName,
              })
            }}
          </p>
          <p>
            {{ docText("controller.contact_prefix") }}
            <a :href="contactHref">{{ contactEmail }}</a
            >.
          </p>
          <p>{{ docText("controller.early_access") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("data.title") }}</h2>
          <p>{{ docText("data.intro") }}</p>
          <ul>
            <li v-for="item in privacyDataItems" :key="item">
              <strong>{{ docText(`data.items.${item}.label`) }}:</strong>
              {{ docText(`data.items.${item}.text`) }}
            </li>
          </ul>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("purposes.title") }}</h2>
          <ul>
            <li v-for="item in privacyPurposeItems" :key="item">
              <strong>{{ docText(`purposes.items.${item}.label`) }}:</strong>
              {{ docText(`purposes.items.${item}.text`) }}
            </li>
          </ul>
        </section>

        <section id="cookies" class="scroll-mt-28 space-y-4">
          <div class="flex items-center gap-2">
            <Cookie class="size-5 text-primary" />
            <h2>{{ docText("cookies.title") }}</h2>
          </div>
          <p>{{ docText("cookies.technical") }}</p>
          <p>{{ docText("cookies.analytics") }}</p>
          <div class="overflow-x-auto rounded-md border border-border">
            <table class="min-w-full divide-y divide-border text-sm">
              <thead class="bg-muted/40 text-left">
                <tr>
                  <th class="px-4 py-3 font-semibold">{{ docText("cookies.table.name") }}</th>
                  <th class="px-4 py-3 font-semibold">{{ docText("cookies.table.type") }}</th>
                  <th class="px-4 py-3 font-semibold">{{ docText("cookies.table.purpose") }}</th>
                  <th class="px-4 py-3 font-semibold">{{ docText("cookies.table.duration") }}</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-border">
                <tr v-for="row in cookieRows" :key="row">
                  <td class="px-4 py-3 font-mono text-xs">{{ docText(`cookies.rows.${row}.name`) }}</td>
                  <td class="px-4 py-3">{{ docText(`cookies.rows.${row}.type`) }}</td>
                  <td class="px-4 py-3">{{ docText(`cookies.rows.${row}.purpose`) }}</td>
                  <td class="px-4 py-3">{{ docText(`cookies.rows.${row}.duration`) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p>{{ docText("cookies.control") }}</p>
          <Button class="gap-2" @click="openCookieSettings">
            <SlidersHorizontal class="size-4" />
            {{ docText("cookies.manage") }}
          </Button>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("providers.title") }}</h2>
          <p>{{ docText("providers.intro") }}</p>
          <ul>
            <li v-for="provider in providerRows" :key="provider">
              <strong>{{ docText(`providers.items.${provider}.label`) }}:</strong>
              {{ docText(`providers.items.${provider}.text`) }}
            </li>
          </ul>
          <p>{{ docText("providers.transfers") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("retention.title") }}</h2>
          <p>{{ docText("retention.main") }}</p>
          <p>{{ docText("retention.technical") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("rights.title") }}</h2>
          <p>
            {{ docText("rights.text_prefix") }}
            <a :href="contactHref">{{ contactEmail }}</a
            >. {{ docText("rights.text_suffix") }}
          </p>
        </section>
      </article>

      <article v-else class="legal-document space-y-12 py-12">
        <section class="space-y-4">
          <h2>{{ docText("notice.title") }}</h2>
          <p>
            {{
              docText("notice.identity", {
                controllerAddress,
                controllerName,
              })
            }}
          </p>
          <p>
            {{ docText("notice.contact_prefix") }}
            <a :href="contactHref">{{ contactEmail }}</a
            >.
          </p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("beta.title") }}</h2>
          <p>{{ docText("beta.text") }}</p>
          <p>{{ docText("beta.payments") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("account.title") }}</h2>
          <p>{{ docText("account.text") }}</p>
          <p>{{ docText("account.age") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("content.title") }}</h2>
          <p>{{ docText("content.ownership") }}</p>
          <p>{{ docText("content.responsibility") }}</p>
          <p>{{ docText("content.expression") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("acceptable.title") }}</h2>
          <p>{{ docText("acceptable.intro") }}</p>
          <ul>
            <li v-for="item in acceptableUseItems" :key="item">
              {{ docText(`acceptable.items.${item}`) }}
            </li>
          </ul>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("providers.title") }}</h2>
          <p>
            {{ docText("providers.text") }}
            <a href="/privacy" data-phx-link="redirect" data-phx-link-state="push">
              {{ docText("providers.privacy_link") }}</a
            >.
          </p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("liability.title") }}</h2>
          <p>{{ docText("liability.availability") }}</p>
          <p>{{ docText("liability.limits") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("law.title") }}</h2>
          <p>{{ docText("law.text") }}</p>
        </section>

        <section class="space-y-4">
          <h2>{{ docText("contact.title") }}</h2>
          <p>
            {{ docText("contact.text_prefix") }}
            <a :href="contactHref">{{ contactEmail }}</a
            >.
          </p>
        </section>
      </article>
    </main>

    <LandingFooter />
  </div>
</template>

<style scoped>
.legal-document h2 {
  font-size: 1.35rem;
  font-weight: 700;
  letter-spacing: 0;
  line-height: 1.25;
}

.legal-document p,
.legal-document li {
  color: hsl(var(--muted-foreground));
  font-size: 0.98rem;
  line-height: 1.8;
}

.legal-document ul {
  display: grid;
  gap: 0.65rem;
  list-style: disc;
  padding-left: 1.25rem;
}

.legal-document a {
  color: hsl(var(--primary));
  font-weight: 600;
  text-underline-offset: 4px;
}

.legal-document a:hover {
  text-decoration: underline;
}
</style>
