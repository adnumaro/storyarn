defmodule Storyarn.Screenplays.Export.FountainTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.Export.Fountain

  # Helper to build element maps
  defp el(type, content \\ "", opts \\ []) do
    position = Keyword.get(opts, :position, 0)
    data = Keyword.get(opts, :data, %{})
    %{type: type, content: content, position: position, data: data}
  end

  # -------------------------------------------------------------------------
  # Title page
  # -------------------------------------------------------------------------

  describe "title page" do
    test "full title page with all fields" do
      elements = [
        el("title_page", "",
          data: %{
            "title" => "LA TABERNA DEL CUERVO",
            "credit" => "Written by",
            "author" => "Studio Dev",
            "draft_date" => "February 2026",
            "contact" => "studio@example.com"
          }
        )
      ]

      result = Fountain.export(elements)

      assert result =~ "Title: LA TABERNA DEL CUERVO"
      assert result =~ "Credit: Written by"
      assert result =~ "Author: Studio Dev"
      assert result =~ "Draft date: February 2026"
      assert result =~ "Contact: studio@example.com"
    end

    test "partial title page skips nil fields" do
      elements = [
        el("title_page", "", data: %{"title" => "My Script", "author" => "Me"})
      ]

      result = Fountain.export(elements)

      assert result =~ "Title: My Script"
      assert result =~ "Author: Me"
      refute result =~ "Credit:"
      refute result =~ "Draft date:"
      refute result =~ "Contact:"
    end

    test "no title page" do
      elements = [el("action", "He walks.", position: 0)]
      result = Fountain.export(elements)

      refute result =~ "Title:"
      assert result =~ "He walks."
    end
  end

  # -------------------------------------------------------------------------
  # Element types
  # -------------------------------------------------------------------------

  describe "element types" do
    test "scene_heading" do
      result = Fountain.export([el("scene_heading", "INT. OFFICE - DAY")])
      assert result =~ "\nINT. OFFICE - DAY\n"
    end

    test "action" do
      result = Fountain.export([el("action", "He walks into the room.")])
      assert result =~ "\nHe walks into the room.\n"
    end

    test "character" do
      result = Fountain.export([el("character", "JOHN")])
      assert result =~ "\nJOHN\n"
    end

    test "dialogue" do
      result = Fountain.export([el("dialogue", "Hello, world!")])
      assert result =~ "Hello, world!\n"
    end

    test "parenthetical" do
      result = Fountain.export([el("parenthetical", "(whispering)")])
      assert result =~ "(whispering)\n"
    end

    test "parenthetical ensures wrapping parens" do
      result = Fountain.export([el("parenthetical", "yelling")])
      assert result =~ "(yelling)\n"
    end

    test "transition" do
      result = Fountain.export([el("transition", "CUT TO:")])
      assert result =~ "\nCUT TO:\n"
    end

    test "page_break" do
      result = Fountain.export([el("page_break")])
      assert result =~ "\n===\n"
    end

    test "section level 1" do
      result = Fountain.export([el("section", "Act One", data: %{"level" => 1})])
      assert result =~ "\n# Act One\n"
    end

    test "section level 2" do
      result = Fountain.export([el("section", "Scene 1", data: %{"level" => 2})])
      assert result =~ "\n## Scene 1\n"
    end

    test "note" do
      result = Fountain.export([el("note", "Director's note")])
      assert result =~ "\n[[Director's note]]\n"
    end

    test "dual dialogue" do
      data = %{
        "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
        "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi there."}
      }

      result = Fountain.export([el("dual_dialogue", "", data: data)])

      assert result =~ "\nALICE\n"
      assert result =~ "Hello.\n"
      assert result =~ "\nBOB ^\n"
      assert result =~ "Hi there.\n"
    end

    test "dual dialogue with parenthetical" do
      data = %{
        "left" => %{
          "character" => "ALICE",
          "parenthetical" => "(whispering)",
          "dialogue" => "Hello."
        },
        "right" => %{
          "character" => "BOB",
          "parenthetical" => "(shouting)",
          "dialogue" => "HI!"
        }
      }

      result = Fountain.export([el("dual_dialogue", "", data: data)])

      assert result =~ "(whispering)\n"
      assert result =~ "(shouting)\n"
    end
  end

  # -------------------------------------------------------------------------
  # Rich text (HTML → Fountain marks)
  # -------------------------------------------------------------------------

  describe "rich text conversion" do
    test "<strong> → **text**" do
      result = Fountain.export([el("action", "<strong>bold</strong>")])
      assert result =~ "**bold**"
    end

    test "<b> → **text**" do
      result = Fountain.export([el("action", "<b>bold</b>")])
      assert result =~ "**bold**"
    end

    test "<em> → *text*" do
      result = Fountain.export([el("action", "<em>italic</em>")])
      assert result =~ "*italic*"
    end

    test "<i> → *text*" do
      result = Fountain.export([el("action", "<i>italic</i>")])
      assert result =~ "*italic*"
    end

    test "<s> stripped" do
      result = Fountain.export([el("action", "<s>struck</s>")])
      assert result =~ "struck"
      refute result =~ "<s>"
      refute result =~ "~"
    end

    test "<br> → newline" do
      result = Fountain.export([el("action", "line one<br>line two")])
      assert result =~ "line one\nline two"
    end

    test "nested marks" do
      result = Fountain.export([el("action", "<strong><em>bold italic</em></strong>")])
      assert result =~ "***bold italic***"
    end

    test "mentions → plain text" do
      html =
        ~s(<span class="mention" data-type="sheet" data-id="1" data-label="MC">#MC</span>)

      result = Fountain.export([el("action", "Meet #{html} now.")])
      assert result =~ "Meet MC now."
      refute result =~ "mention"
    end

    test "plain text passthrough" do
      result = Fountain.export([el("action", "Plain text here.")])
      assert result =~ "Plain text here."
    end
  end

  # -------------------------------------------------------------------------
  # Skip types
  # -------------------------------------------------------------------------

  describe "skip types" do
    test "conditional is silently omitted" do
      elements = [
        el("action", "Before.", position: 0),
        el("conditional", "", position: 1, data: %{"condition" => %{}}),
        el("action", "After.", position: 2)
      ]

      result = Fountain.export(elements)

      assert result =~ "Before."
      assert result =~ "After."
      refute result =~ "conditional"
    end

    test "instruction is silently omitted" do
      elements = [
        el("action", "Walk.", position: 0),
        el("instruction", "", position: 1, data: %{"assignments" => []})
      ]

      result = Fountain.export(elements)
      assert result =~ "Walk."
      refute result =~ "instruction"
    end

    test "response is silently omitted" do
      elements = [
        el("action", "Walk.", position: 0),
        el("response", "", position: 1, data: %{"choices" => []})
      ]

      result = Fountain.export(elements)
      assert result =~ "Walk."
      refute result =~ "response"
    end

    test "hub_marker and jump_marker are silently omitted" do
      elements = [
        el("action", "Walk.", position: 0),
        el("hub_marker", "", position: 1),
        el("jump_marker", "", position: 2)
      ]

      result = Fountain.export(elements)
      assert result =~ "Walk."
      refute result =~ "hub"
      refute result =~ "jump"
    end
  end

  # -------------------------------------------------------------------------
  # Full document
  # -------------------------------------------------------------------------

  # -------------------------------------------------------------------------
  # Round-trip: export → import
  # -------------------------------------------------------------------------

  describe "round-trip: export → import" do
    test "standard element types survive export→import" do
      alias Storyarn.Screenplays.Import.Fountain, as: FountainImport

      elements = [
        el("scene_heading", "INT. OFFICE - DAY", position: 0),
        el("action", "A desk sits in the corner.", position: 1),
        el("character", "JOHN", position: 2),
        el("dialogue", "Hello there.", position: 3),
        el("transition", "CUT TO:", position: 4),
        el("scene_heading", "EXT. PARK - NIGHT", position: 5),
        el("action", "It is dark outside.", position: 6)
      ]

      fountain_text = Fountain.export(elements)
      parsed = FountainImport.parse(fountain_text)

      # Verify type preservation
      original_types = Enum.map(elements, & &1.type)
      parsed_types = Enum.map(parsed, & &1.type)
      assert original_types == parsed_types

      # Verify content preservation
      assert Enum.find(parsed, &(&1.type == "scene_heading")).content == "INT. OFFICE - DAY"
      assert Enum.find(parsed, &(&1.type == "action")).content == "A desk sits in the corner."
      assert Enum.find(parsed, &(&1.type == "character")).content == "JOHN"
      assert Enum.find(parsed, &(&1.type == "dialogue")).content == "Hello there."
      assert Enum.find(parsed, &(&1.type == "transition")).content == "CUT TO:"
    end

    test "title page survives export→import" do
      alias Storyarn.Screenplays.Import.Fountain, as: FountainImport

      elements = [
        el("title_page", "",
          position: 0,
          data: %{
            "title" => "My Script",
            "credit" => "Written by",
            "author" => "Studio Dev"
          }
        ),
        el("scene_heading", "INT. OFFICE - DAY", position: 1)
      ]

      fountain_text = Fountain.export(elements)
      parsed = FountainImport.parse(fountain_text)

      tp = Enum.find(parsed, &(&1.type == "title_page"))
      assert tp
      assert tp.data["title"] == "My Script"
      assert tp.data["credit"] == "Written by"
      assert tp.data["author"] == "Studio Dev"
    end

    test "bold and italic marks survive export→import round trip" do
      alias Storyarn.Screenplays.Import.Fountain, as: FountainImport

      elements = [
        el("scene_heading", "INT. OFFICE - DAY", position: 0),
        el("action", "<strong>bold</strong> and <em>italic</em> text", position: 1)
      ]

      fountain_text = Fountain.export(elements)
      parsed = FountainImport.parse(fountain_text)

      action = Enum.find(parsed, &(&1.type == "action"))
      assert action.content =~ "<strong>bold</strong>"
      assert action.content =~ "<em>italic</em>"
    end

    test "sections and notes survive export→import" do
      alias Storyarn.Screenplays.Import.Fountain, as: FountainImport

      elements = [
        el("section", "Act One", position: 0, data: %{"level" => 1}),
        el("action", "The story begins.", position: 1),
        el("note", "Director note here", position: 2)
      ]

      fountain_text = Fountain.export(elements)
      parsed = FountainImport.parse(fountain_text)

      section = Enum.find(parsed, &(&1.type == "section"))
      assert section
      assert section.content == "Act One"
      assert section.data["level"] == 1

      note = Enum.find(parsed, &(&1.type == "note"))
      assert note
      assert note.content == "Director note here"
    end
  end

  describe "full document" do
    test "title page + body combined" do
      elements = [
        el("title_page", "",
          position: 0,
          data: %{"title" => "My Script", "author" => "Me"}
        ),
        el("scene_heading", "INT. OFFICE - DAY", position: 1),
        el("action", "A desk sits in the corner.", position: 2),
        el("character", "JOHN", position: 3),
        el("dialogue", "Hello there.", position: 4)
      ]

      result = Fountain.export(elements)

      assert result =~ "Title: My Script"
      assert result =~ "Author: Me"
      assert result =~ "INT. OFFICE - DAY"
      assert result =~ "A desk sits in the corner."
      assert result =~ "JOHN"
      assert result =~ "Hello there."
    end

    test "empty list → empty output" do
      assert Fountain.export([]) == ""
    end
  end
end
