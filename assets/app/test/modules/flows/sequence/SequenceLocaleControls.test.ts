import { mount } from "@vue/test-utils";
import SequenceLocaleControls from "@modules/flows/sequence/components/SequenceLocaleControls.vue";
import type {
  SequenceDialogueVoice,
  SequenceLocalizationState,
} from "@modules/flows/sequence/types";

describe("SequenceLocaleControls", () => {
  it.each([
    [{ isSource: true, status: "source" }, "source"],
    [{ isSource: false, status: "approved" }, "current"],
    [{ isSource: false, status: "missing" }, "missing"],
    [{ isSource: false, status: "missing", fallback: true }, "fallback"],
    [{ isSource: false, status: "translated", stale: true }, "stale"],
  ] satisfies Array<[SequenceLocalizationState, string]>)(
    "normalizes translation state as %s",
    (localizationStatus, expected) => {
      const wrapper = mount(SequenceLocaleControls, {
        props: { id: "translation-test", localizationStatus },
      });

      expect(wrapper.get("[data-translation-status]").attributes("data-translation-status")).toBe(
        expected,
      );
    },
  );

  it.each([
    [{ status: "none", available: false }, "none"],
    [{ status: "needed", available: false }, "needed"],
    [{ status: "recorded", available: true, url: "/voice.mp3" }, "recorded"],
    [{ status: "approved", available: true, url: "/voice.mp3" }, "approved"],
    [{ status: "approved", stale: true, available: false }, "stale"],
    [{ status: "approved", available: false, url: null }, "unavailable"],
  ] satisfies Array<[SequenceDialogueVoice, string]>)(
    "normalizes voice state as %s",
    (voice, expected) => {
      const wrapper = mount(SequenceLocaleControls, {
        props: { id: "voice-test", voice },
      });

      expect(wrapper.get("[data-voice-status]").attributes("data-voice-status")).toBe(expected);
    },
  );
});
