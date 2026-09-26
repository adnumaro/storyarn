import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vitest";
import LogicToggle from "@modules/flows/editor/components/expression/builders/condition/LogicToggle.vue";
import { setTestLocale } from "../../../setup";

afterEach(() => setTestLocale("en"));

// The label, the two choices and the words after them, as the user reads them.
function wordingOf(wrapper: VueWrapper): string[] {
  const spans = wrapper.findAll(":scope > span");
  return [spans[0].text(), ...wrapper.findAll("button").map((b) => b.text()), spans[1].text()];
}

describe("Flows LogicToggle", () => {
  it("words the condition match so it agrees in Spanish", () => {
    setTestLocale("es");
    const parts = (props: Record<string, unknown>) => wordingOf(mount(LogicToggle, { props }));

    expect(parts({ logic: "all", kind: "rules" })).toEqual([
      "Cumplir",
      "todas",
      "alguna",
      "las reglas",
    ]);
    expect(parts({ logic: "any", kind: "group" })).toEqual([
      "Cumplir",
      "todos",
      "alguno",
      "de los bloques del grupo",
    ]);
  });
});
