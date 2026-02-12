defmodule Storyarn.Screenplays.AutoDetectTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.AutoDetect

  describe "detect_type/1" do
    test "detects INT. scene heading" do
      assert AutoDetect.detect_type("INT. LIVING ROOM - DAY") == "scene_heading"
    end

    test "detects EXT. scene heading" do
      assert AutoDetect.detect_type("EXT. PARK - NIGHT") == "scene_heading"
    end

    test "detects INT./EXT. scene heading" do
      assert AutoDetect.detect_type("INT./EXT. CAR - DAY") == "scene_heading"
    end

    test "detects I/E. scene heading" do
      assert AutoDetect.detect_type("I/E. PORCH - DUSK") == "scene_heading"
    end

    test "scene heading is case-insensitive" do
      assert AutoDetect.detect_type("int. kitchen - night") == "scene_heading"
    end

    test "detects CUT TO: transition" do
      assert AutoDetect.detect_type("CUT TO:") == "transition"
    end

    test "detects DISSOLVE TO: transition" do
      assert AutoDetect.detect_type("DISSOLVE TO:") == "transition"
    end

    test "detects FADE IN: transition" do
      assert AutoDetect.detect_type("FADE IN:") == "transition"
    end

    test "detects FADE OUT. transition" do
      assert AutoDetect.detect_type("FADE OUT.") == "transition"
    end

    test "detects FADE TO BLACK. transition" do
      assert AutoDetect.detect_type("FADE TO BLACK.") == "transition"
    end

    test "detects simple character name" do
      assert AutoDetect.detect_type("JOHN") == "character"
    end

    test "detects character with extension" do
      assert AutoDetect.detect_type("SARAH (V.O.)") == "character"
    end

    test "detects character with O.S. extension" do
      assert AutoDetect.detect_type("JAMES (O.S.)") == "character"
    end

    test "detects multi-word character" do
      assert AutoDetect.detect_type("DR. SMITH") == "character"
    end

    test "detects parenthetical" do
      assert AutoDetect.detect_type("(whispering)") == "parenthetical"
    end

    test "detects parenthetical with spaces" do
      assert AutoDetect.detect_type("(to himself, quietly)") == "parenthetical"
    end

    test "returns nil for normal action text" do
      assert AutoDetect.detect_type("He walks away.") == nil
    end

    test "returns nil for empty string" do
      assert AutoDetect.detect_type("") == nil
    end

    test "returns nil for whitespace only" do
      assert AutoDetect.detect_type("   ") == nil
    end

    test "returns nil for mixed-case text" do
      assert AutoDetect.detect_type("John walks into the room.") == nil
    end

    test "detects EST. as scene heading" do
      assert AutoDetect.detect_type("EST. CITY SKYLINE - DAY") == "scene_heading"
    end

    test "detects INTERCUT: as transition" do
      assert AutoDetect.detect_type("INTERCUT:") == "transition"
    end

    test "detects character with multiple extensions" do
      assert AutoDetect.detect_type("JAIME (V.O.) (CONT'D)") == "character"
    end

    test "detects character with hyphenated name" do
      assert AutoDetect.detect_type("JOHN-PAUL") == "character"
    end

    test "detects character with apostrophe" do
      assert AutoDetect.detect_type("O'BRIEN") == "character"
    end
  end
end
