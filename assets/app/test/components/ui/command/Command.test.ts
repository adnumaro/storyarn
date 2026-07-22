import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import {
  Command,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "../../../../components/ui/command";

function mountCommand(disableFilter = false) {
  return mount({
    components: {
      Command,
      CommandGroup,
      CommandInput,
      CommandItem,
      CommandList,
    },
    template: `
      <Command :disable-filter="disableFilter">
        <CommandInput />
        <CommandList>
          <CommandGroup>
            <CommandItem value="visible-name">Visible Name</CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    `,
    data: () => ({ disableFilter }),
  });
}

describe("Command", () => {
  it("filters items by default", async () => {
    const wrapper = mountCommand();

    await wrapper.find("[data-slot='command-input']").setValue("shortcut-only");

    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(0);
  });

  it("can disable internal filtering for remotely filtered result sets", async () => {
    const wrapper = mountCommand(true);

    await wrapper.find("[data-slot='command-input']").setValue("shortcut-only");

    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(1);
  });

  it("restores every item and group when the search contains only whitespace", async () => {
    const wrapper = mountCommand();
    const input = wrapper.find("[data-slot='command-input']");

    await input.setValue("shortcut-only");
    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(0);

    await input.setValue("   ");

    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(1);
    expect(wrapper.find("[data-slot='command-group']").attributes("hidden")).toBeUndefined();
  });
});
