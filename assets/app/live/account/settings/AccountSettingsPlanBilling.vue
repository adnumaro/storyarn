<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import {
  METER_WARNING_RATIO,
  SettingsMeterRow,
  SettingsPage,
  SettingsSection,
  type SettingsMeterStatus,
} from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";

interface CountBucket {
  used: number;
  /** `paid_seats` on paid plans, `null` when the plan does not define the limit. */
  limit: number | "unlimited" | "paid_seats" | null;
}

interface Account {
  plan: { key: string; name: string };
  seats: CountBucket;
  workspaces: CountBucket;
}

interface Meter {
  key: string;
  label: string;
  hint: string;
  used: string;
  limit: string | null;
  percent: number | null;
  status: SettingsMeterStatus;
  statusLabel: string;
}

const { account, contactPath } = defineProps<{
  account: Account;
  contactPath: string;
}>();

const { locale, t, te } = useI18n();

const planName = computed(() => {
  const key = `settings.plan_billing.plans.${account.plan.key}`;
  return te(key) ? t(key) : account.plan.name;
});

function meter(key: "seats" | "workspaces", bucket: CountBucket): Meter {
  const format = new Intl.NumberFormat(locale.value);
  const base = {
    key,
    label: t(`settings.plan_billing.meters.${key}`),
    hint: t(`settings.plan_billing.hints.${key}`),
    used: format.format(bucket.used),
    limit: null,
    percent: null,
  };

  if (bucket.limit === "paid_seats") {
    return {
      ...base,
      status: "unlimited",
      statusLabel: t("settings.plan_billing.status.paid_seats"),
    };
  }

  if (bucket.limit === "unlimited") {
    return {
      ...base,
      status: "unlimited",
      statusLabel: t("settings.plan_billing.status.unlimited"),
    };
  }

  if (bucket.limit === null) {
    return { ...base, status: "unknown", statusLabel: t("settings.plan_billing.status.unknown") };
  }

  const percent = bucket.limit > 0 ? Math.min((bucket.used / bucket.limit) * 100, 100) : 100;
  let status: SettingsMeterStatus = "available";
  if (bucket.used >= bucket.limit) status = "reached";
  else if (percent >= METER_WARNING_RATIO * 100) status = "warning";

  return {
    ...base,
    limit: format.format(bucket.limit),
    percent,
    status,
    statusLabel: t(`settings.plan_billing.status.${status}`),
  };
}

const meters = computed<Meter[]>(() => [
  meter("seats", account.seats),
  meter("workspaces", account.workspaces),
]);
</script>

<template>
  <SettingsPage :title="t('settings.plan_billing.title')">
    <SettingsSection :title="t('settings.plan_billing.plan_section')">
      <div
        class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3.5 sm:grid-cols-[minmax(0,1fr)_auto]"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-medium" data-testid="account-plan-name">{{ planName }}</span>
            <Badge>{{ t("settings.plan_billing.current_plan") }}</Badge>
          </div>
          <div class="text-[13px] text-muted-foreground">
            {{ t("settings.plan_billing.plan_hint") }}
          </div>
        </div>
        <div class="flex items-center justify-end">
          <Button as-child variant="outline" size="sm">
            <LiveLink :to="contactPath">{{ t("settings.plan_billing.talk_to_us") }}</LiveLink>
          </Button>
        </div>
      </div>
    </SettingsSection>

    <SettingsSection
      :title="t('settings.plan_billing.usage_section')"
      :hint="t('settings.plan_billing.usage_hint')"
    >
      <SettingsMeterRow
        v-for="row in meters"
        :key="row.key"
        :data-testid="`account-plan-meter-${row.key}`"
        :label="row.label"
        :hint="row.hint"
        :used="row.used"
        :limit="row.limit"
        :percent="row.percent"
        :status="row.status"
        :status-label="row.statusLabel"
      />
    </SettingsSection>
  </SettingsPage>
</template>
