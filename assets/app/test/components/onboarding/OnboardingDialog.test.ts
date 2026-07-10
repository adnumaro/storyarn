import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import type { App } from "vue";
import OnboardingDialog from "../../../components/onboarding/OnboardingDialog.vue";
import { sessionKey } from "../../../components/onboarding/onboardingGuides";
import { createMockLive } from "../../setup";
import type { LiveInterface } from "../../../shared/composables/useLive";

const dialogStubs = {
  Dialog: { template: "<div><slot /></div>" },
  DialogContent: { template: "<section><slot /></section>" },
  DialogDescription: { template: "<div><slot /></div>" },
  DialogHeader: { template: "<header><slot /></header>" },
  DialogTitle: { template: "<h2><slot /></h2>" },
};

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountDialog(props: { guideKey?: string; autoShow?: boolean } = {}) {
  const live = createMockLive();
  const wrapper = mount(OnboardingDialog, {
    props: {
      guideKey: "flows",
      autoShow: false,
      ...props,
    },
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
      stubs: dialogStubs,
    },
  });

  return { live, wrapper };
}

describe("OnboardingDialog", () => {
  beforeEach(() => window.sessionStorage.clear());

  it("tracks an automatic opening when the guide is not snoozed", () => {
    const { live } = mountDialog({ autoShow: true });

    expect(live.pushEvent).toHaveBeenCalledWith(
      "onboarding_tutorial_interaction",
      {
        tutorial: "flows",
        action: "opened",
        source: "auto",
      },
      undefined,
    );
  });

  it("snoozes the guide for the browser session", async () => {
    const { live, wrapper } = mountDialog();

    await wrapper.get('[data-testid="onboarding-not-now"]').trigger("click");

    expect(window.sessionStorage.getItem(sessionKey("flows"))).toBe("1");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "onboarding_tutorial_interaction",
      {
        tutorial: "flows",
        action: "snoozed",
        source: "manual",
      },
      undefined,
    );
  });

  it("completes the tutorial after the final step", async () => {
    const { live, wrapper } = mountDialog();

    await wrapper.get('[data-testid="onboarding-next"]').trigger("click");
    await wrapper.get('[data-testid="onboarding-next"]').trigger("click");
    await wrapper.get('[data-testid="onboarding-finish"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "complete_onboarding_tutorial",
      {
        tutorial: "flows",
        source: "manual",
      },
      undefined,
    );
  });

  it("does not render unsupported client keys", () => {
    const { wrapper } = mountDialog({ guideKey: "unknown" });

    expect(wrapper.find("section").exists()).toBe(false);
  });
});
