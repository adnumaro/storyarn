defmodule Storyarn.Screenplays.ScreenplayElementTest do
  use Storyarn.DataCase

  alias Storyarn.Screenplays.ScreenplayElement

  describe "types/0" do
    test "returns all 16 element types" do
      types = ScreenplayElement.types()
      assert length(types) == 16
      assert "scene_heading" in types
      assert "action" in types
      assert "character" in types
      assert "dialogue" in types
      assert "parenthetical" in types
      assert "transition" in types
      assert "dual_dialogue" in types
      assert "conditional" in types
      assert "instruction" in types
      assert "response" in types
      assert "hub_marker" in types
      assert "jump_marker" in types
      assert "note" in types
      assert "section" in types
      assert "page_break" in types
      assert "title_page" in types
    end
  end

  describe "standard_types/0" do
    test "returns text-based types" do
      types = ScreenplayElement.standard_types()
      assert "scene_heading" in types
      assert "action" in types
      assert "character" in types
      assert "dialogue" in types
      assert "parenthetical" in types
      assert "transition" in types
      assert "dual_dialogue" in types
      assert "note" in types
      assert "section" in types
      assert "page_break" in types
      assert "title_page" in types
      # Should not include interactive or marker types
      refute "conditional" in types
      refute "hub_marker" in types
    end
  end

  describe "interactive_types/0" do
    test "returns conditional, instruction, response" do
      assert ScreenplayElement.interactive_types() == ~w(conditional instruction response)
    end
  end

  describe "flow_marker_types/0" do
    test "returns hub_marker and jump_marker" do
      assert ScreenplayElement.flow_marker_types() == ~w(hub_marker jump_marker)
    end
  end

  describe "dialogue_group_types/0" do
    test "returns character, dialogue, parenthetical" do
      assert ScreenplayElement.dialogue_group_types() == ~w(character dialogue parenthetical)
    end
  end

  describe "non_mappeable_types/0" do
    test "returns note, section, page_break, title_page" do
      assert ScreenplayElement.non_mappeable_types() == ~w(note section page_break title_page)
    end
  end

  describe "create_changeset/2" do
    test "valid with type only" do
      changeset = ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "action"})
      assert changeset.valid?
    end

    test "valid for each element type" do
      for type <- ScreenplayElement.types() do
        changeset = ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: type})
        assert changeset.valid?, "Expected type #{type} to be valid"
      end
    end

    test "requires type" do
      changeset = ScreenplayElement.create_changeset(%ScreenplayElement{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).type
    end

    test "rejects invalid type" do
      changeset = ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "invalid"})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end

    test "accepts content and data" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "scene_heading",
          content: "INT. TAVERN - NIGHT",
          data: %{"key" => "value"}
        })

      assert changeset.valid?
      assert get_change(changeset, :content) == "INT. TAVERN - NIGHT"
      assert get_change(changeset, :data) == %{"key" => "value"}
    end

    test "accepts position" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "action", position: 5})

      assert changeset.valid?
      assert get_change(changeset, :position) == 5
    end

    test "rejects negative position" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "action", position: -1})

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).position
    end

    test "accepts depth" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "dialogue", depth: 2})

      assert changeset.valid?
      assert get_change(changeset, :depth) == 2
    end

    test "rejects negative depth" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "action", depth: -1})

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).depth
    end

    test "accepts branch nil" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{type: "action", branch: nil})

      assert changeset.valid?
    end

    test "accepts branch true" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "dialogue",
          branch: "true"
        })

      assert changeset.valid?
      assert get_change(changeset, :branch) == "true"
    end

    test "accepts branch false" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "dialogue",
          branch: "false"
        })

      assert changeset.valid?
      assert get_change(changeset, :branch) == "false"
    end

    test "rejects invalid branch value" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "action",
          branch: "maybe"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).branch
    end
  end

  describe "update_changeset/2" do
    test "updates content" do
      element = %ScreenplayElement{type: "action", content: "Old text"}

      changeset = ScreenplayElement.update_changeset(element, %{content: "New text"})
      assert changeset.valid?
      assert get_change(changeset, :content) == "New text"
    end

    test "updates data" do
      element = %ScreenplayElement{type: "conditional", data: %{}}

      changeset =
        ScreenplayElement.update_changeset(element, %{
          data: %{"condition" => %{"logic" => "all", "rules" => []}}
        })

      assert changeset.valid?
    end

    test "changes element type" do
      element = %ScreenplayElement{type: "action", content: "JAIME"}

      changeset = ScreenplayElement.update_changeset(element, %{type: "character"})
      assert changeset.valid?
      assert get_change(changeset, :type) == "character"
    end

    test "rejects invalid type on update" do
      element = %ScreenplayElement{type: "action"}

      changeset = ScreenplayElement.update_changeset(element, %{type: "bogus"})
      refute changeset.valid?
    end

    test "updates depth and branch" do
      element = %ScreenplayElement{type: "dialogue", depth: 0, branch: nil}

      changeset = ScreenplayElement.update_changeset(element, %{depth: 1, branch: "true"})
      assert changeset.valid?
      assert get_change(changeset, :depth) == 1
      assert get_change(changeset, :branch) == "true"
    end
  end

  describe "position_changeset/2" do
    test "updates position" do
      element = %ScreenplayElement{type: "action", position: 0}

      changeset = ScreenplayElement.position_changeset(element, %{position: 3})
      assert changeset.valid?
      assert get_change(changeset, :position) == 3
    end

    test "keeps existing position when no change provided" do
      element = %ScreenplayElement{type: "action", position: 5}

      changeset = ScreenplayElement.position_changeset(element, %{})
      assert changeset.valid?
      # No change, keeps existing value
      refute get_change(changeset, :position)
    end

    test "rejects negative position" do
      element = %ScreenplayElement{type: "action", position: 0}

      changeset = ScreenplayElement.position_changeset(element, %{position: -1})
      refute changeset.valid?
    end
  end

  describe "link_node_changeset/2" do
    test "sets linked_node_id" do
      element = %ScreenplayElement{type: "dialogue", linked_node_id: nil}

      changeset = ScreenplayElement.link_node_changeset(element, %{linked_node_id: 42})
      assert changeset.valid?
      assert get_change(changeset, :linked_node_id) == 42
    end

    test "clears linked_node_id" do
      element = %ScreenplayElement{type: "dialogue", linked_node_id: 42}

      changeset = ScreenplayElement.link_node_changeset(element, %{linked_node_id: nil})
      assert changeset.valid?
      assert get_change(changeset, :linked_node_id) == nil
    end
  end
end
