import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import CtaSignup from "@modules/public/landing/sections/cta/CtaSignup.vue";

// The CTA section renders at `opacity-0` until `useRevealOnScroll` sees it
// intersect. That only happens if the template ref actually reaches the
// composable — and a bare `ref="sectionRef"` is invisible to `noUnusedLocals`,
// so the binding looks like dead code to the type-checker. This test pins the
// runtime behaviour so the wiring cannot be "cleaned up" away.
const observe = vi.fn();

beforeEach(() => {
  observe.mockClear();
  vi.stubGlobal(
    "IntersectionObserver",
    class {
      observe = observe;
      unobserve = vi.fn();
      disconnect = vi.fn();
    },
  );
});

describe("CtaSignup", () => {
  it("hands the rendered <section> to the reveal observer", () => {
    const wrapper = mount(CtaSignup, {
      props: { registrationUrl: "/register" },
      attachTo: document.body,
      global: { stubs: { LiveLink: { name: "LiveLink", template: "<a><slot /></a>" } } },
    });

    expect(observe).toHaveBeenCalledTimes(1);
    expect(observe).toHaveBeenCalledWith(wrapper.find("section").element);
  });
});
