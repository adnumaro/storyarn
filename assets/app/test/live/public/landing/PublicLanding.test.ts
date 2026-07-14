import { shallowMount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import PublicLanding from "../../../../live/public/landing/PublicLanding.vue";

beforeEach(() => {
  window.history.replaceState({ scroll: 0 }, "", window.location.href);
  vi.stubGlobal(
    "requestAnimationFrame",
    vi.fn((callback: FrameRequestCallback) => {
      callback(0);
      return 1;
    }),
  );
  vi.stubGlobal("cancelAnimationFrame", vi.fn());
  vi.stubGlobal(
    "matchMedia",
    vi.fn(() => ({ matches: false }) as MediaQueryList),
  );
  vi.spyOn(window, "scrollTo").mockImplementation(() => undefined);
});

afterEach(() => {
  window.history.replaceState(null, "", window.location.href);
  document.documentElement.classList.remove("dark");
  document.documentElement.style.scrollBehavior = "";
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("PublicLanding", () => {
  it("restores the saved top position after the async landing surface mounts", () => {
    const wrapper = shallowMount(PublicLanding, {
      props: {
        registrationUrl: "/users/register",
      },
    });

    expect(window.scrollTo).toHaveBeenCalledWith(0, 0);
    expect(document.documentElement.style.scrollBehavior).toBe("smooth");

    wrapper.unmount();
  });

  it("cancels a pending scroll restoration when the landing unmounts", () => {
    vi.mocked(window.requestAnimationFrame).mockImplementation(() => 42);

    const wrapper = shallowMount(PublicLanding, {
      props: {
        registrationUrl: "/users/register",
      },
    });

    wrapper.unmount();

    expect(window.cancelAnimationFrame).toHaveBeenCalledWith(42);
    expect(window.scrollTo).not.toHaveBeenCalled();
  });
});
