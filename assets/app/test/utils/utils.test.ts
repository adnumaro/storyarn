import { cn } from "@utils/utils";

describe("cn", () => {
  it("merges simple class strings", () => {
    expect(cn("foo", "bar")).toBe("foo bar");
  });

  it("handles a single class", () => {
    expect(cn("px-4")).toBe("px-4");
  });

  it("handles no arguments", () => {
    expect(cn()).toBe("");
  });

  it("filters out falsy values", () => {
    expect(cn("foo", false, null, undefined, 0, "", "bar")).toBe("foo bar");
  });

  it("handles conditional classes", () => {
    const isActive = true;
    const isDisabled = false;
    expect(cn("base", isActive && "active", isDisabled && "disabled")).toBe("base active");
  });

  it("resolves Tailwind conflicts (last wins)", () => {
    expect(cn("px-4", "px-2")).toBe("px-2");
    expect(cn("text-red-500", "text-blue-500")).toBe("text-blue-500");
    expect(cn("bg-white", "bg-black")).toBe("bg-black");
  });

  it("preserves non-conflicting Tailwind classes", () => {
    expect(cn("px-4", "py-2")).toBe("px-4 py-2");
    expect(cn("text-sm", "font-bold")).toBe("text-sm font-bold");
  });

  it("handles array inputs via clsx", () => {
    expect(cn(["foo", "bar"])).toBe("foo bar");
  });

  it("handles object inputs via clsx", () => {
    expect(cn({ foo: true, bar: false, baz: true })).toBe("foo baz");
  });

  it("handles mixed inputs", () => {
    expect(cn("base", ["arr1", "arr2"], { conditional: true })).toBe("base arr1 arr2 conditional");
  });

  it("resolves complex Tailwind conflicts", () => {
    expect(cn("p-4", "p-2")).toBe("p-2");
    expect(cn("mt-4 mb-2", "mt-8")).toBe("mb-2 mt-8");
  });
});
