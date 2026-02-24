defmodule Storyarn.Flows.HubColorsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.HubColors

  describe "default_hex/0" do
    test "returns a hex color string" do
      assert "#" <> _ = HubColors.default_hex()
    end
  end

  describe "to_hex/1" do
    test "returns nil for nil input" do
      assert HubColors.to_hex(nil) == nil
    end

    test "passes through hex string" do
      assert HubColors.to_hex("#ff0000") == "#ff0000"
    end
  end

  describe "to_hex/2 with default" do
    test "returns default for nil input" do
      assert HubColors.to_hex(nil, "#123456") == "#123456"
    end

    test "returns default for empty string" do
      assert HubColors.to_hex("", "#123456") == "#123456"
    end

    test "passes through non-empty hex" do
      assert HubColors.to_hex("#ff0000", "#123456") == "#ff0000"
    end
  end
end
