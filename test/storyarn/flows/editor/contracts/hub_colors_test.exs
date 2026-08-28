defmodule Storyarn.Flows.HubColorsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.HubColors

  describe "default_hex/0" do
    test "returns a hex color string" do
      assert "#" <> _ = HubColors.default_hex()
    end
  end

  describe "resolve/1" do
    test "returns the default for nil input" do
      assert HubColors.resolve(nil) == HubColors.default_hex()
    end

    test "returns the default for an invalid color" do
      assert HubColors.resolve("not-a-color") == HubColors.default_hex()
    end

    test "rejects legacy named colors from the current contract" do
      assert HubColors.resolve("blue") == HubColors.default_hex()
    end

    test "passes through short hex colors" do
      assert HubColors.resolve("#f00") == "#f00"
    end

    test "passes through six-digit hex colors" do
      assert HubColors.resolve("#ff0000") == "#ff0000"
    end

    test "passes through eight-digit hex colors" do
      assert HubColors.resolve("#ff000080") == "#ff000080"
    end

    test "rejects otherwise valid hex colors with trailing newlines" do
      assert HubColors.resolve("#ff0000\n") == HubColors.default_hex()
      assert HubColors.resolve("#ff0000\r\n") == HubColors.default_hex()
    end
  end

  describe "resolve_legacy/1" do
    test "resolves historical color names to their original hex values" do
      assert HubColors.resolve_legacy("purple") == "#8b5cf6"
      assert HubColors.resolve_legacy("blue") == "#3b82f6"
      assert HubColors.resolve_legacy("green") == "#22c55e"
      assert HubColors.resolve_legacy("yellow") == "#f59e0b"
      assert HubColors.resolve_legacy("amber") == "#f59e0b"
      assert HubColors.resolve_legacy("red") == "#ef4444"
      assert HubColors.resolve_legacy("pink") == "#ec4899"
      assert HubColors.resolve_legacy("orange") == "#f97316"
      assert HubColors.resolve_legacy("cyan") == "#06b6d4"
    end

    test "preserves valid hex values and defaults invalid values" do
      assert HubColors.resolve_legacy("#3b82f6") == "#3b82f6"
      assert HubColors.resolve_legacy("not-a-color") == HubColors.default_hex()
      assert HubColors.resolve_legacy(nil) == HubColors.default_hex()
    end
  end
end
