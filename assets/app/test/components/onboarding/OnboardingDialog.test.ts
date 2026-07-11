import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick, type App } from "vue";
import OnboardingDialog from "../../../components/onboarding/OnboardingDialog.vue";
import { sessionKey } from "../../../components/onboarding/onboardingGuides";
import { createMockLive } from "../../setup";
import type { LiveInterface } from "../../../shared/composables/useLive";

const dialogStubs = {
  Dialog: { props: ["open"], template: '<div v-if="open"><slot /></div>' },
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
  afterEach(() => vi.restoreAllMocks());

  it("tracks an automatic opening when the guide is not snoozed", async () => {
    const { live, wrapper } = mountDialog({ autoShow: true });

    await nextTick();

    expect(wrapper.find('[data-testid="onboarding-not-now"]').exists()).toBe(true);
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

    wrapper.vm.openTutorial();
    await nextTick();
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

    wrapper.vm.openTutorial();
    await nextTick();
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

  it("auto-opens when LiveVue enables the guide after mount", async () => {
    const { live, wrapper } = mountDialog();

    expect(wrapper.find('[data-testid="onboarding-not-now"]').exists()).toBe(false);

    await wrapper.setProps({ autoShow: true });

    expect(wrapper.find('[data-testid="onboarding-not-now"]').exists()).toBe(true);
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

  it("completes and closes when session storage is unavailable", async () => {
    const { live, wrapper } = mountDialog();
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("Storage disabled", "SecurityError");
    });

    wrapper.vm.openTutorial();
    await nextTick();
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
    expect(wrapper.find('[data-testid="onboarding-finish"]').exists()).toBe(false);
  });

  it("does not render unsupported client keys", () => {
    const { wrapper } = mountDialog({ guideKey: "unknown" });

    expect(wrapper.find("section").exists()).toBe(false);
  });
});
