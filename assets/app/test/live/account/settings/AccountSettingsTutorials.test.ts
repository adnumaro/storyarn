import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import type { App } from "vue";
import AccountSettingsTutorials from "../../../../live/account/settings/AccountSettingsTutorials.vue";
import { sessionKey } from "../../../../components/onboarding/onboardingGuides";
import { createMockLive } from "../../../setup";
import type { LiveInterface } from "../../../../shared/composables/useLive";

const tutorials = [
  { key: "workspace", state: "completed" as const },
  { key: "flows", state: "pending" as const },
];

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountSettings() {
  const live = createMockLive();
  const wrapper = mount(AccountSettingsTutorials, {
    props: { tutorials },
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
    },
  });

  return { live, wrapper };
}

describe("AccountSettingsTutorials", () => {
  beforeEach(() => window.sessionStorage.clear());

  it("restarts one guide and clears its session snooze", async () => {
    window.sessionStorage.setItem(sessionKey("flows"), "1");
    const { live, wrapper } = mountSettings();

    await wrapper.get('[data-testid="restart-tutorial-flows"]').trigger("click");

    expect(window.sessionStorage.getItem(sessionKey("flows"))).toBeNull();
    expect(live.pushEvent).toHaveBeenCalledWith(
      "restart_tutorial",
      { tutorial: "flows" },
      undefined,
    );
  });

  it("restarts every guide", async () => {
    const { live, wrapper } = mountSettings();

    await wrapper.get('[data-testid="restart-all-tutorials"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("restart_all_tutorials", {}, undefined);
  });
});
