<script setup lang="ts">
import { useLiveVue } from "live_vue";
import { ArrowRight } from "lucide-vue-next";
import { computed, ref, type Ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useRevealOnScroll } from "../../composables/useRevealOnScroll";
import { capture } from "@/js/utils/posthog";

interface WaitlistOptions {
  professions: string[];
  primary_interests: string[];
  discovery_sources: string[];
  current_tools: string[];
}

interface WaitlistReply {
  status?: "ok" | "error";
  message?: string;
}

defineProps<{
  options: WaitlistOptions;
}>();

const live = useLiveVue();
const { t } = useI18n();
const email = ref("");
const profession = ref("");
const primaryInterest = ref("");
const discoverySource = ref("");
const currentTool = ref("");
const currentToolOther = ref("");
const submitting = ref(false);
const detailsSubmitting = ref(false);
const detailsModalOpen = ref(false);
const feedbackMessage = ref("");
const feedbackStatus = ref<"success" | "error" | null>(null);
const detailsFeedbackMessage = ref("");
const detailsFeedbackStatus = ref<"success" | "error" | null>(null);

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();

const canSubmit = computed(() => {
  return Boolean(email.value.trim() && !submitting.value);
});

const canSubmitDetails = computed(() => {
  const hasRequiredFields =
    profession.value && primaryInterest.value && discoverySource.value && currentTool.value;
  const hasToolDetail = currentTool.value !== "other" || currentToolOther.value.trim();

  return Boolean(hasRequiredFields && hasToolDetail && !detailsSubmitting.value);
});

function metricLabel(group: string, value: string) {
  return t(`landing.cta.metrics.${group}.options.${value}`);
}

function updateSelection(target: Ref<string>, value: string | string[]) {
  target.value = Array.isArray(value) ? value[0] || "" : value;
}

function updateProfession(value: string | string[]) {
  updateSelection(profession, value);
}

function updatePrimaryInterest(value: string | string[]) {
  updateSelection(primaryInterest, value);
}

function updateDiscoverySource(value: string | string[]) {
  updateSelection(discoverySource, value);
}

function updateCurrentTool(value: string | string[]) {
  updateSelection(currentTool, value);
}

function resetDetails() {
  profession.value = "";
  primaryInterest.value = "";
  discoverySource.value = "";
  currentTool.value = "";
  currentToolOther.value = "";
  detailsFeedbackMessage.value = "";
  detailsFeedbackStatus.value = null;
}

async function handleSubmit() {
  const submittedEmail = email.value.trim();
  if (!canSubmit.value) return;

  submitting.value = true;
  feedbackMessage.value = "";
  feedbackStatus.value = null;

  try {
    const reply = (await live.pushEvent("join_waitlist", {
      email: submittedEmail,
    })) as WaitlistReply;

    if (reply.status === "error") {
      feedbackStatus.value = "error";
      feedbackMessage.value = reply.message || t("landing.cta.error");
      return;
    }

    capture("waitlist joined");
    email.value = "";
    resetDetails();
    feedbackStatus.value = "success";
    feedbackMessage.value = t("landing.cta.success");
    detailsModalOpen.value = true;
  } catch {
    feedbackStatus.value = "error";
    feedbackMessage.value = t("landing.cta.error");
  } finally {
    submitting.value = false;
  }
}

async function handleDetailsSubmit() {
  if (!canSubmitDetails.value) return;

  detailsSubmitting.value = true;
  detailsFeedbackMessage.value = "";
  detailsFeedbackStatus.value = null;

  try {
    const reply = (await live.pushEvent("save_waitlist_details", {
      profession: profession.value,
      primary_interest: primaryInterest.value,
      discovery_source: discoverySource.value,
      current_tool: currentTool.value,
      current_tool_other: currentToolOther.value.trim(),
    })) as WaitlistReply;

    if (reply.status === "error") {
      detailsFeedbackStatus.value = "error";
      detailsFeedbackMessage.value = reply.message || t("landing.cta.details_error");
      return;
    }

    capture("waitlist details submitted", {
      profession: profession.value,
      primary_interest: primaryInterest.value,
      discovery_source: discoverySource.value,
      current_tool: currentTool.value,
    });
    detailsFeedbackStatus.value = "success";
    detailsFeedbackMessage.value = t("landing.cta.details_success");
    feedbackStatus.value = "success";
    feedbackMessage.value = t("landing.cta.details_success");
    detailsModalOpen.value = false;
  } catch {
    detailsFeedbackStatus.value = "error";
    detailsFeedbackMessage.value = t("landing.cta.details_error");
  } finally {
    detailsSubmitting.value = false;
  }
}
</script>

<template>
  <section
    id="waitlist"
    ref="sectionRef"
    class="scroll-mt-32 py-36"
    :class="{ 'opacity-0 translate-y-7': !isRevealed, 'opacity-100 translate-y-0': isRevealed }"
    style="
      transition:
        opacity 1s cubic-bezier(0.22, 1, 0.36, 1),
        transform 1s cubic-bezier(0.22, 1, 0.36, 1);
    "
  >
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <div
        class="lp-cta-band relative overflow-hidden rounded-4xl border border-border bg-muted/80 p-10"
      >
        <div class="relative z-10">
          <h2
            class="mb-3 text-[clamp(2rem,3vw,3.4rem)] font-bold leading-[0.96] tracking-[-0.06em] text-foreground"
          >
            {{ $t("landing.cta.title") }}
          </h2>
          <p class="mb-2 max-w-160 leading-relaxed text-muted-foreground">
            {{ $t("landing.cta.desc") }}
          </p>
          <form
            class="mt-6 flex max-w-xl flex-col gap-3 sm:flex-row"
            @submit.prevent.stop="handleSubmit"
          >
            <div class="min-w-0 flex-1">
              <Input
                id="waitlist-email"
                v-model="email"
                type="email"
                :aria-label="$t('landing.cta.metrics.email.label')"
                :placeholder="$t('landing.cta.placeholder')"
                required
                class="h-12 rounded-lg border-border/40 bg-zinc-950/40 px-4 text-[15px]"
              />
            </div>
            <Button
              type="submit"
              :disabled="!canSubmit"
              class="h-12 shrink-0 rounded-lg border-0 px-6! text-[15px] font-bold text-teal-950 transition-all hover:scale-105 gap-2"
              style="
                background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210));
                box-shadow:
                  0 0 20px rgba(34, 211, 238, 0.4),
                  inset 0 1px 0 rgba(255, 255, 255, 0.3);
              "
            >
              {{ submitting ? $t("landing.cta.submitting") : $t("landing.cta.btn") }}
              <ArrowRight class="size-4" />
            </Button>
          </form>
          <p
            v-if="feedbackMessage"
            :role="feedbackStatus === 'error' ? 'alert' : 'status'"
            aria-live="polite"
            :class="[
              'mt-3 text-sm',
              feedbackStatus === 'error' ? 'text-destructive' : 'text-primary',
            ]"
          >
            {{ feedbackMessage }}
          </p>
          <p class="mt-3 text-xs text-foreground/40">
            {{ $t("landing.cta.footer") }}
          </p>
        </div>
      </div>
    </div>

    <Dialog v-model:open="detailsModalOpen">
      <DialogContent class="w-[calc(100vw-2rem)] max-w-md">
        <DialogHeader>
          <DialogTitle>{{ $t("landing.cta.details_modal.title") }}</DialogTitle>
          <DialogDescription>
            {{ $t("landing.cta.details_modal.desc") }}
          </DialogDescription>
        </DialogHeader>

        <form
          id="waitlist-details-form"
          class="grid gap-5"
          @submit.prevent.stop="handleDetailsSubmit"
        >
          <div class="grid gap-5">
            <div class="space-y-2.5">
              <Label for="waitlist-profession">{{
                $t("landing.cta.metrics.profession.label")
              }}</Label>
              <Select :model-value="profession" required @update:model-value="updateProfession">
                <SelectTrigger id="waitlist-profession" class="h-11 w-full">
                  <SelectValue :placeholder="$t('landing.cta.metrics.profession.placeholder')" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem v-for="option in options.professions" :key="option" :value="option">
                    {{ metricLabel("profession", option) }}
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div class="space-y-2.5">
              <Label for="waitlist-interest">{{
                $t("landing.cta.metrics.primary_interest.label")
              }}</Label>
              <Select
                :model-value="primaryInterest"
                required
                @update:model-value="updatePrimaryInterest"
              >
                <SelectTrigger id="waitlist-interest" class="h-11 w-full">
                  <SelectValue
                    :placeholder="$t('landing.cta.metrics.primary_interest.placeholder')"
                  />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem
                    v-for="option in options.primary_interests"
                    :key="option"
                    :value="option"
                  >
                    {{ metricLabel("primary_interest", option) }}
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div class="space-y-2.5">
              <Label for="waitlist-source">{{
                $t("landing.cta.metrics.discovery_source.label")
              }}</Label>
              <Select
                :model-value="discoverySource"
                required
                @update:model-value="updateDiscoverySource"
              >
                <SelectTrigger id="waitlist-source" class="h-11 w-full">
                  <SelectValue
                    :placeholder="$t('landing.cta.metrics.discovery_source.placeholder')"
                  />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem
                    v-for="option in options.discovery_sources"
                    :key="option"
                    :value="option"
                  >
                    {{ metricLabel("discovery_source", option) }}
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div class="space-y-2.5">
              <Label for="waitlist-tool">{{ $t("landing.cta.metrics.current_tool.label") }}</Label>
              <Select :model-value="currentTool" required @update:model-value="updateCurrentTool">
                <SelectTrigger id="waitlist-tool" class="h-11 w-full">
                  <SelectValue :placeholder="$t('landing.cta.metrics.current_tool.placeholder')" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem v-for="option in options.current_tools" :key="option" :value="option">
                    {{ metricLabel("current_tool", option) }}
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div v-if="currentTool === 'other'" class="space-y-2.5">
            <Label for="waitlist-tool-other">{{
              $t("landing.cta.metrics.current_tool_other.label")
            }}</Label>
            <Input
              id="waitlist-tool-other"
              v-model="currentToolOther"
              :placeholder="$t('landing.cta.metrics.current_tool_other.placeholder')"
              maxlength="120"
              required
            />
          </div>

          <p
            v-if="detailsFeedbackMessage"
            :role="detailsFeedbackStatus === 'error' ? 'alert' : 'status'"
            aria-live="polite"
            :class="[
              'text-sm',
              detailsFeedbackStatus === 'error' ? 'text-destructive' : 'text-primary',
            ]"
          >
            {{ detailsFeedbackMessage }}
          </p>
        </form>

        <DialogFooter class="justify-end pt-1">
          <Button form="waitlist-details-form" type="submit" :disabled="!canSubmitDetails">
            {{
              detailsSubmitting
                ? $t("landing.cta.details_modal.saving")
                : $t("landing.cta.details_modal.save")
            }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </section>
</template>

<style scoped>
.lp-cta-band::after {
  content: "";
  position: absolute;
  width: 22rem;
  height: 22rem;
  right: -6rem;
  bottom: -10rem;
  border-radius: 50%;
  background: hsl(var(--primary) / 0.14);
  filter: blur(80px);
}
</style>
