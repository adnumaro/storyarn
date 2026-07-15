import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import type { App } from "vue";
import AccountSettingsTutorials from "../../../../live/account/settings/AccountSettingsTutorials.vue";
import { sessionKey } from "../../../../components/onboarding/onboardingGuides";
import { createMockLive, setTestLocale } from "../../../setup";
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
  beforeEach(() => {
    window.sessionStorage.clear();
    document.documentElement.lang = "en";
    setTestLocale("en");
    document.documentElement.dataset.publicDefaultLocale = "en";
    document.documentElement.dataset.publicLocales = "en,es";
    document.documentElement.dataset.publicLocaleConfig = JSON.stringify([
      { gettext_locale: "en", language_tag: "en", path_segment: "en" },
      { gettext_locale: "es", language_tag: "es", path_segment: "es" },
    ]);
  });

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

  it("links to documentation in the current published public locale", () => {
    document.documentElement.lang = "es";
    setTestLocale("es");
    const { wrapper } = mountSettings();

    expect(wrapper.find('a[href="/es/docs/quick-start/create-workspace"]').exists()).toBe(true);
    expect(wrapper.find('a[href="/es/docs/narrative-design/flows-overview"]').exists()).toBe(true);
  });
});
