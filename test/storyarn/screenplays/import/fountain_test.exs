defmodule Storyarn.Screenplays.Import.FountainTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.Import.Fountain

  # -------------------------------------------------------------------------
  # Title page
  # -------------------------------------------------------------------------

  describe "title page" do
    test "full title page" do
      text = """
      Title: LA TABERNA DEL CUERVO
      Credit: Written by
      Author: Studio Dev
      Draft date: February 2026
      Contact: studio@example.com

      INT. OFFICE - DAY
      """

      result = Fountain.parse(text)
      tp = Enum.find(result, &(&1.type == "title_page"))

      assert tp
      assert tp.data["title"] == "LA TABERNA DEL CUERVO"
      assert tp.data["credit"] == "Written by"
      assert tp.data["author"] == "Studio Dev"
      assert tp.data["draft_date"] == "February 2026"
      assert tp.data["contact"] == "studio@example.com"
    end

    test "partial title page" do
      text = """
      Title: My Script

      FADE IN:
      """

      result = Fountain.parse(text)
      tp = Enum.find(result, &(&1.type == "title_page"))

      assert tp
      assert tp.data["title"] == "My Script"
      refute Map.has_key?(tp.data, "author")
    end

    test "no title page when first line is not key:value" do
      text = """
      INT. OFFICE - DAY

      He walks in.
      """

      result = Fountain.parse(text)
      refute Enum.any?(result, &(&1.type == "title_page"))
    end
  end

  # -------------------------------------------------------------------------
  # Scene headings
  # -------------------------------------------------------------------------

  describe "scene headings" do
    test "INT." do
      result = Fountain.parse("INT. OFFICE - DAY")
      assert [%{type: "scene_heading", content: "INT. OFFICE - DAY"}] = result
    end

    test "EXT." do
      result = Fountain.parse("EXT. PARK - NIGHT")
      assert [%{type: "scene_heading", content: "EXT. PARK - NIGHT"}] = result
    end

    test "INT./EXT." do
      result = Fountain.parse("INT./EXT. CAR - DAY")
      assert [%{type: "scene_heading", content: "INT./EXT. CAR - DAY"}] = result
    end

    test "forced with ." do
      result = Fountain.parse(".FLASHBACK")
      assert [%{type: "scene_heading", content: "FLASHBACK"}] = result
    end
  end

  # -------------------------------------------------------------------------
  # Action
  # -------------------------------------------------------------------------

  describe "action" do
    test "plain action" do
      result = Fountain.parse("INT. OFFICE - DAY\n\nHe walks into the room.")
      action = Enum.find(result, &(&1.type == "action"))
      assert action.content == "He walks into the room."
    end

    test "forced action with !" do
      result = Fountain.parse("!JOHN walks to the door.")
      assert [%{type: "action", content: "JOHN walks to the door."}] = result
    end

    test "multi-line action" do
      text = "INT. OFFICE - DAY\n\nHe walks in.\nShe stands up."
      result = Fountain.parse(text)
      action = Enum.find(result, &(&1.type == "action"))
      assert action.content =~ "He walks in."
    end
  end

  # -------------------------------------------------------------------------
  # Character + Dialogue + Parenthetical
  # -------------------------------------------------------------------------

  describe "character and dialogue" do
    test "character followed by dialogue" do
      text = "INT. OFFICE - DAY\n\nJOHN\n\nHello there."
      result = Fountain.parse(text)

      types = Enum.map(result, & &1.type)
      assert "character" in types
      assert "dialogue" in types

      char = Enum.find(result, &(&1.type == "character"))
      assert char.content == "JOHN"

      dial = Enum.find(result, &(&1.type == "dialogue"))
      assert dial.content == "Hello there."
    end

    test "character with parenthetical and dialogue" do
      text = "JOHN\n\n(whispering)\n\nHello there."
      result = Fountain.parse(text)

      types = Enum.map(result, & &1.type)
      assert "character" in types
      assert "parenthetical" in types
      assert "dialogue" in types
    end

    test "character with extensions (V.O.)" do
      text = "JOHN (V.O.)\n\nHello there."
      result = Fountain.parse(text)
      char = Enum.find(result, &(&1.type == "character"))
      assert char.content == "JOHN (V.O.)"
    end

    test "forced character with @" do
      text = "@McCOY\n\nWhat do you think?"
      result = Fountain.parse(text)
      char = Enum.find(result, &(&1.type == "character"))
      assert char.content == "McCOY"
    end
  end

  # -------------------------------------------------------------------------
  # Transitions
  # -------------------------------------------------------------------------

  describe "transitions" do
    test "CUT TO:" do
      text = "INT. OFFICE - DAY\n\nCUT TO:"
      result = Fountain.parse(text)
      trans = Enum.find(result, &(&1.type == "transition"))
      assert trans.content == "CUT TO:"
    end

    test "forced with >" do
      text = "> FADE TO BLACK"
      result = Fountain.parse(text)
      assert [%{type: "transition", content: "FADE TO BLACK"}] = result
    end
  end

  # -------------------------------------------------------------------------
  # Page break
  # -------------------------------------------------------------------------

  describe "page break" do
    test "===" do
      text = "Action before.\n\n===\n\nAction after."
      result = Fountain.parse(text)
      assert Enum.any?(result, &(&1.type == "page_break"))
    end
  end

  # -------------------------------------------------------------------------
  # Sections
  # -------------------------------------------------------------------------

  describe "sections" do
    test "level 1" do
      result = Fountain.parse("# Act One")
      assert [%{type: "section", content: "Act One", data: %{"level" => 1}}] = result
    end

    test "level 2" do
      result = Fountain.parse("## Scene 1")
      assert [%{type: "section", content: "Scene 1", data: %{"level" => 2}}] = result
    end
  end

  # -------------------------------------------------------------------------
  # Notes
  # -------------------------------------------------------------------------

  describe "notes" do
    test "[[text]]" do
      result = Fountain.parse("[[This is a note]]")
      assert [%{type: "note", content: "This is a note"}] = result
    end
  end

  # -------------------------------------------------------------------------
  # Dual dialogue
  # -------------------------------------------------------------------------

  describe "dual dialogue" do
    test "character with ^ marker" do
      text = "ALICE\n\nHello!\n\nBOB ^\n\nHi there!"
      result = Fountain.parse(text)

      # Should have two characters and two dialogues
      chars = Enum.filter(result, &(&1.type == "character"))
      assert length(chars) == 2

      bob = Enum.find(chars, &(&1.content == "BOB"))
      assert bob
      assert bob.data["dual"] == true
    end
  end

  # -------------------------------------------------------------------------
  # Fountain marks → HTML
  # -------------------------------------------------------------------------

  describe "fountain marks → HTML conversion" do
    test "**bold** → <strong>" do
      result = Fountain.parse("INT. OFFICE - DAY\n\n**bold text** here.")
      action = Enum.find(result, &(&1.type == "action"))
      assert action.content =~ "<strong>bold text</strong>"
    end

    test "*italic* → <em>" do
      result = Fountain.parse("INT. OFFICE - DAY\n\n*italic text* here.")
      action = Enum.find(result, &(&1.type == "action"))
      assert action.content =~ "<em>italic text</em>"
    end

    test "***bold italic*** → <strong><em>" do
      result = Fountain.parse("INT. OFFICE - DAY\n\n***bold italic*** here.")
      action = Enum.find(result, &(&1.type == "action"))
      assert action.content =~ "<strong><em>bold italic</em></strong>"
    end
  end

  # -------------------------------------------------------------------------
  # Complete document
  # -------------------------------------------------------------------------

  describe "complete document" do
    test "full fountain script" do
      text = """
      Title: My Script
      Author: Me

      INT. OFFICE - DAY

      JOHN walks into the room.

      JOHN

      Hello, world!

      CUT TO:

      EXT. PARK - NIGHT

      It's dark outside.
      """

      result = Fountain.parse(text)

      types = Enum.map(result, & &1.type)
      assert "title_page" in types
      assert "scene_heading" in types
      assert "action" in types
      assert "character" in types
      assert "dialogue" in types
      assert "transition" in types

      # Positions are sequential
      positions = Enum.map(result, & &1.position)
      assert positions == Enum.to_list(0..(length(result) - 1))
    end
  end

  # -------------------------------------------------------------------------
  # Round-trip: import → export
  # -------------------------------------------------------------------------

  describe "round-trip: import → export" do
    test "standard fountain script survives import→export" do
      alias Storyarn.Screenplays.Export.Fountain, as: FountainExport

      input = "INT. OFFICE - DAY\n\nJOHN walks into the room.\n\nJOHN\n\nHello there.\n\nCUT TO:\n\nEXT. PARK - NIGHT\n\nIt is dark outside."

      parsed = Fountain.parse(input)
      output = FountainExport.export(parsed)

      assert output =~ "INT. OFFICE - DAY"
      assert output =~ "JOHN walks into the room."
      assert output =~ "JOHN"
      assert output =~ "Hello there."
      assert output =~ "CUT TO:"
      assert output =~ "EXT. PARK - NIGHT"
      assert output =~ "It is dark outside."
    end

    test "title page survives import→export" do
      alias Storyarn.Screenplays.Export.Fountain, as: FountainExport

      input = "Title: My Script\nAuthor: Studio Dev\n\nINT. OFFICE - DAY"

      parsed = Fountain.parse(input)
      output = FountainExport.export(parsed)

      assert output =~ "Title: My Script"
      assert output =~ "Author: Studio Dev"
      assert output =~ "INT. OFFICE - DAY"
    end

    test "bold and italic marks survive import→export round trip" do
      alias Storyarn.Screenplays.Export.Fountain, as: FountainExport

      input = "INT. OFFICE - DAY\n\n**bold** and *italic* text here."

      parsed = Fountain.parse(input)
      output = FountainExport.export(parsed)

      assert output =~ "**bold**"
      assert output =~ "*italic*"
    end
  end

  # -------------------------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------------------------

  describe "edge cases" do
    test "empty input" do
      assert Fountain.parse("") == []
    end

    test "whitespace-only input" do
      assert Fountain.parse("   \n\n  ") == []
    end

    test "nil-like input" do
      assert Fountain.parse(nil) == []
    end
  end
end
