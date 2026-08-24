defmodule Storyarn.Shared.StringUtilsTest do
  @moduledoc """
  Two predicates that were copied around the codebase.

  `blank?/1` had eight byte-equivalent copies (`nil` or `""` → true, everything
  else false) and three deliberately different ones that also trim — those keep
  their own definitions, because collapsing them would silently change what
  counts as an empty sheet block or scene label.

  `present_label/2` was byte-identical in four dashboard/health modules. It DOES
  trim, so it is not `blank?/1` with a fallback bolted on; the two live side by
  side precisely so the difference stays visible.
  """
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Shared.StringUtils

  describe "blank?/1" do
    test "is true for nil and the empty string" do
      assert StringUtils.blank?(nil)
      assert StringUtils.blank?("")
    end

    test "is false for any non-empty string" do
      refute StringUtils.blank?("a")
      refute StringUtils.blank?("Hero")
    end

    test "does NOT trim — whitespace is present" do
      refute StringUtils.blank?(" "),
             "the trimming variants in the health checkers are deliberately separate; do not fold them in here"

      refute StringUtils.blank?("\n")
    end

    test "is false for non-string terms rather than raising" do
      refute StringUtils.blank?(0)
      refute StringUtils.blank?(false)
      refute StringUtils.blank?([])
      refute StringUtils.blank?(%{})
    end
  end

  describe "present_label/2" do
    test "returns the value when it carries something" do
      assert StringUtils.present_label("Hero", "Sheet") == "Hero"
    end

    test "falls back on the empty string" do
      assert StringUtils.present_label("", "Sheet") == "Sheet"
    end

    test "falls back on whitespace-only input — unlike blank?/1, it trims" do
      assert StringUtils.present_label("   ", "Sheet") == "Sheet"
      assert StringUtils.present_label("\t\n", "Sheet") == "Sheet"
    end

    test "falls back on nil and on any non-binary term" do
      assert StringUtils.present_label(nil, "Sheet") == "Sheet"
      assert StringUtils.present_label(42, "Sheet") == "Sheet"
      assert StringUtils.present_label(%{}, "Sheet") == "Sheet"
    end

    test "keeps surrounding whitespace on a value it does return" do
      assert StringUtils.present_label(" Hero ", "Sheet") == " Hero ",
             "trimming decides presence only; the label itself is returned untouched"
    end
  end
end
