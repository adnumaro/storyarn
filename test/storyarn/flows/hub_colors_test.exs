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

    test "passes through short hex colors" do
      assert HubColors.resolve("#f00") == "#f00"
    end

    test "passes through six-digit hex colors" do
      assert HubColors.resolve("#ff0000") == "#ff0000"
    end

    test "passes through eight-digit hex colors" do
      assert HubColors.resolve("#ff000080") == "#ff000080"
    end
  end
end
