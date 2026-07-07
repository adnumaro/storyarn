import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import PasswordInput from "../../../components/forms/PasswordInput.vue";

function mountInput() {
  return mount(PasswordInput, {
    props: {
      modelValue: "secret",
    },
    attrs: {
      id: "password-input",
      name: "user[password]",
      autocomplete: "current-password",
      required: true,
    },
  });
}

describe("PasswordInput", () => {
  it("renders a hidden password input by default", () => {
    const wrapper = mountInput();
    const input = wrapper.get("#password-input");
    const toggle = wrapper.get("button");

    expect(input.attributes("type")).toBe("password");
    expect(input.attributes("name")).toBe("user[password]");
    expect(toggle.attributes("aria-label")).toBe("Show password");
    expect(toggle.attributes("aria-pressed")).toBe("false");
  });

  it("toggles password visibility without changing the field value", async () => {
    const wrapper = mountInput();
    const input = wrapper.get("#password-input");
    const toggle = wrapper.get("button");

    await toggle.trigger("click");

    expect(input.attributes("type")).toBe("text");
    expect((input.element as HTMLInputElement).value).toBe("secret");
    expect(toggle.attributes("aria-label")).toBe("Hide password");
    expect(toggle.attributes("aria-pressed")).toBe("true");

    await toggle.trigger("click");

    expect(input.attributes("type")).toBe("password");
    expect((input.element as HTMLInputElement).value).toBe("secret");
    expect(toggle.attributes("aria-label")).toBe("Show password");
    expect(toggle.attributes("aria-pressed")).toBe("false");
  });
});
