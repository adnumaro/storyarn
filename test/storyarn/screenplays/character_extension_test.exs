defmodule Storyarn.Screenplays.CharacterExtensionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.CharacterExtension

  describe "parse/1" do
    test "plain name returns empty extensions" do
      assert CharacterExtension.parse("JAIME") == %{base_name: "JAIME", extensions: []}
    end

    test "extracts V.O. extension" do
      assert CharacterExtension.parse("JAIME (V.O.)") == %{base_name: "JAIME", extensions: ["V.O."]}
    end

    test "extracts O.S. extension" do
      assert CharacterExtension.parse("ALICE (O.S.)") == %{base_name: "ALICE", extensions: ["O.S."]}
    end

    test "extracts CONT'D extension" do
      assert CharacterExtension.parse("JAIME (CONT'D)") == %{base_name: "JAIME", extensions: ["CONT'D"]}
    end

    test "extracts multiple extensions" do
      result = CharacterExtension.parse("JAIME (V.O.) (CONT'D)")
      assert result.base_name == "JAIME"
      assert result.extensions == ["V.O.", "CONT'D"]
    end

    test "handles nil input" do
      assert CharacterExtension.parse(nil) == %{base_name: "", extensions: []}
    end

    test "handles empty string" do
      assert CharacterExtension.parse("") == %{base_name: "", extensions: []}
    end

    test "handles name with extra whitespace" do
      assert CharacterExtension.parse("  JAIME  (V.O.)  ") == %{base_name: "JAIME", extensions: ["V.O."]}
    end
  end

  describe "base_name/1" do
    test "returns stripped name without extensions" do
      assert CharacterExtension.base_name("JAIME (V.O.) (CONT'D)") == "JAIME"
    end

    test "returns name as-is when no extensions" do
      assert CharacterExtension.base_name("BOB") == "BOB"
    end

    test "handles nil" do
      assert CharacterExtension.base_name(nil) == ""
    end
  end

  describe "has_contd?/1" do
    test "returns true when CONT'D is present" do
      assert CharacterExtension.has_contd?("JAIME (CONT'D)")
    end

    test "returns true case-insensitive" do
      assert CharacterExtension.has_contd?("jaime (cont'd)")
    end

    test "returns false when not present" do
      refute CharacterExtension.has_contd?("JAIME (V.O.)")
    end

    test "returns false for nil" do
      refute CharacterExtension.has_contd?(nil)
    end

    test "returns false for empty string" do
      refute CharacterExtension.has_contd?("")
    end
  end
end
