import { describe, expect, it } from "vitest";
import { shallowMount } from "@vue/test-utils";
import CommandDialog from "../../../../components/ui/command/CommandDialog.vue";
import { Command } from "../../../../components/ui/command";

describe("CommandDialog", () => {
  it("passes remote-filter ownership to Command instead of the dialog primitive", () => {
    const wrapper = shallowMount(CommandDialog, {
      props: {
        open: true,
        title: "Lookup",
        description: "Search references",
        disableFilter: true,
      },
      global: {
        stubs: {
          Dialog: {
            template: '<div data-dialog v-bind="$attrs"><slot /></div>',
          },
          DialogContent: {
            template: "<div><slot /></div>",
          },
          DialogDescription: {
            template: "<div><slot /></div>",
          },
          DialogHeader: {
            template: "<div><slot /></div>",
          },
          DialogTitle: {
            template: "<div><slot /></div>",
          },
        },
      },
    });

    expect(wrapper.getComponent(Command).props("disableFilter")).toBe(true);
    expect(wrapper.get("[data-dialog]").attributes("disable-filter")).toBeUndefined();
  });
});
