defmodule Storyarn.Shared.ColorUtilsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.ColorUtils

  describe "hex_to_hsl/1" do
    test "returns channels compatible with semantic HSL variables" do
      assert ColorUtils.hex_to_hsl("#ff0000") == "0.0 100.0% 50.0%"
      assert ColorUtils.hex_to_hsl("#7c3aed") == "262.12 83.26% 57.84%"
    end
  end

  describe "contrast_foreground/1" do
    test "uses a light foreground on dark colors" do
      assert ColorUtils.contrast_foreground("#152238") == "#fafafa"
    end

    test "uses a dark foreground on light colors" do
      assert ColorUtils.contrast_foreground("#F5D547") == "#0a0a0a"
    end
  end
end
