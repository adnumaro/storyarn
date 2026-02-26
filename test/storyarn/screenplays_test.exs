defmodule Storyarn.ScreenplaysTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.{Screenplay, ScreenplayElement}

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project}
  end

  # ===========================================================================
  # draft?/1
  # ===========================================================================

  describe "draft?/1" do
    test "returns false for a non-draft screenplay" do
      refute Screenplays.draft?(%Screenplay{draft_of_id: nil})
    end

    test "returns true for a draft screenplay" do
      assert Screenplays.draft?(%Screenplay{draft_of_id: 1})
    end
  end

  # ===========================================================================
  # Screenplay CRUD through facade
  # ===========================================================================

  describe "create_screenplay/2" do
    setup :setup_project

    test "delegates to ScreenplayCrud and creates screenplay", %{project: project} do
      {:ok, screenplay} = Screenplays.create_screenplay(project, %{name: "Test Script"})

      assert screenplay.name == "Test Script"
      assert screenplay.shortcut != nil
      assert screenplay.project_id == project.id
    end

    test "auto-generates shortcut from name", %{project: project} do
      {:ok, screenplay} = Screenplays.create_screenplay(project, %{name: "The Opening"})
      assert screenplay.shortcut == "the-opening"
    end

    test "fails with invalid attrs", %{project: project} do
      {:error, changeset} = Screenplays.create_screenplay(project, %{})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "list_screenplays/1" do
    setup :setup_project

    test "lists non-deleted screenplays", %{project: project} do
      {:ok, s1} = Screenplays.create_screenplay(project, %{name: "One"})
      {:ok, s2} = Screenplays.create_screenplay(project, %{name: "Two"})

      result = Screenplays.list_screenplays(project.id)
      ids = Enum.map(result, & &1.id)

      assert s1.id in ids
      assert s2.id in ids
    end

    test "returns empty list for empty project", %{project: project} do
      assert Screenplays.list_screenplays(project.id) == []
    end
  end

  describe "list_screenplays_tree/1" do
    setup :setup_project

    test "returns tree structure", %{project: project} do
      {:ok, root} = Screenplays.create_screenplay(project, %{name: "Root"})

      {:ok, _child} =
        Screenplays.create_screenplay(project, %{name: "Child", parent_id: root.id})

      tree = Screenplays.list_screenplays_tree(project.id)

      assert length(tree) == 1
      assert hd(tree).name == "Root"
      assert length(hd(tree).children) == 1
    end
  end

  describe "get_screenplay/2" do
    setup :setup_project

    test "returns screenplay with elements preloaded", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "My Script"})
      {:ok, _el} = Screenplays.create_element(sp, %{type: "action", content: "Hello"})

      result = Screenplays.get_screenplay(project.id, sp.id)

      assert result.id == sp.id
      assert length(result.elements) == 1
    end

    test "returns nil for non-existent screenplay", %{project: project} do
      assert Screenplays.get_screenplay(project.id, -1) == nil
    end
  end

  describe "get_screenplay!/2" do
    setup :setup_project

    test "returns screenplay", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "My Script"})
      result = Screenplays.get_screenplay!(project.id, sp.id)
      assert result.id == sp.id
    end

    test "raises for non-existent screenplay", %{project: project} do
      assert_raise Ecto.NoResultsError, fn ->
        Screenplays.get_screenplay!(project.id, -1)
      end
    end
  end

  describe "update_screenplay/2" do
    setup :setup_project

    test "updates screenplay attributes", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Original"})

      {:ok, updated} = Screenplays.update_screenplay(sp, %{name: "Updated"})

      assert updated.name == "Updated"
      assert updated.shortcut == "updated"
    end
  end

  describe "change_screenplay/2" do
    setup :setup_project

    test "returns a changeset", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Test"})
      changeset = Screenplays.change_screenplay(sp, %{name: "New"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns changeset with no attrs", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Test"})
      changeset = Screenplays.change_screenplay(sp)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "screenplay_exists?/2" do
    setup :setup_project

    test "returns true for existing screenplay", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Exists"})
      assert Screenplays.screenplay_exists?(project.id, sp.id)
    end

    test "returns false for deleted screenplay", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Deleted"})
      {:ok, _} = Screenplays.delete_screenplay(sp)
      refute Screenplays.screenplay_exists?(project.id, sp.id)
    end

    test "returns false for non-existent id", %{project: project} do
      refute Screenplays.screenplay_exists?(project.id, -1)
    end
  end

  # ===========================================================================
  # Soft delete + restore through facade
  # ===========================================================================

  describe "integration: screenplay + elements lifecycle" do
    setup :setup_project

    test "create screenplay, add elements, list and verify order", %{project: project} do
      # Create screenplay through facade
      {:ok, screenplay} = Screenplays.create_screenplay(project, %{name: "Test Script"})
      assert screenplay.name == "Test Script"
      assert screenplay.shortcut != nil

      # Add elements through facade
      {:ok, e1} =
        Screenplays.create_element(screenplay, %{
          type: "scene_heading",
          content: "INT. OFFICE - DAY"
        })

      {:ok, e2} =
        Screenplays.create_element(screenplay, %{type: "action", content: "John enters."})

      {:ok, e3} = Screenplays.create_element(screenplay, %{type: "character", content: "JOHN"})

      {:ok, e4} =
        Screenplays.create_element(screenplay, %{type: "dialogue", content: "Hello there."})

      # List elements through facade
      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 4
      assert Enum.map(elements, & &1.id) == [e1.id, e2.id, e3.id, e4.id]
      assert Enum.map(elements, & &1.position) == [0, 1, 2, 3]

      # Count through facade
      assert Screenplays.count_elements(screenplay.id) == 4

      # Group elements through facade
      groups = Screenplays.group_elements(elements)
      types = Enum.map(groups, & &1.type)
      assert types == [:scene_heading, :action, :dialogue_group]
    end

    test "create screenplay, delete, verify soft-deleted, restore", %{project: project} do
      {:ok, screenplay} = Screenplays.create_screenplay(project, %{name: "Deletable"})

      # Verify it's listed
      list = Screenplays.list_screenplays(project.id)
      assert Enum.any?(list, &(&1.id == screenplay.id))

      # Soft-delete
      {:ok, _deleted} = Screenplays.delete_screenplay(screenplay)

      # Not in active list
      list = Screenplays.list_screenplays(project.id)
      refute Enum.any?(list, &(&1.id == screenplay.id))

      # In trash
      trash = Screenplays.list_deleted_screenplays(project.id)
      assert Enum.any?(trash, &(&1.id == screenplay.id))

      # Restore
      deleted = hd(Enum.filter(trash, &(&1.id == screenplay.id)))
      {:ok, restored} = Screenplays.restore_screenplay(deleted)
      assert restored.deleted_at == nil

      # Back in active list
      list = Screenplays.list_screenplays(project.id)
      assert Enum.any?(list, &(&1.id == screenplay.id))
    end
  end

  # ===========================================================================
  # Queries through facade
  # ===========================================================================

  describe "get_with_elements/1" do
    setup :setup_project

    test "returns screenplay with elements ordered by position", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "With Elements"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "action", content: "Second"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "scene_heading", content: "First"})

      result = Screenplays.get_with_elements(sp.id)

      assert result.id == sp.id
      assert length(result.elements) == 2
      positions = Enum.map(result.elements, & &1.position)
      assert positions == [0, 1]
    end

    test "returns nil for deleted screenplay", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Deleted"})
      {:ok, _} = Screenplays.delete_screenplay(sp)

      assert Screenplays.get_with_elements(sp.id) == nil
    end
  end

  describe "count_elements/1" do
    setup :setup_project

    test "returns correct count", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Counting"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "action", content: "One"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "action", content: "Two"})

      assert Screenplays.count_elements(sp.id) == 2
    end

    test "returns 0 for empty screenplay", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Empty"})
      assert Screenplays.count_elements(sp.id) == 0
    end
  end

  describe "list_drafts/1" do
    setup :setup_project

    test "returns drafts of a screenplay", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      result = Screenplays.list_drafts(original.id)
      assert length(result) == 1
      assert hd(result).id == draft.id
    end

    test "returns empty for screenplay with no drafts", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "No Drafts"})
      assert Screenplays.list_drafts(sp.id) == []
    end
  end

  # ===========================================================================
  # Tree Operations through facade
  # ===========================================================================

  describe "reorder_screenplays/3" do
    setup :setup_project

    test "reorders screenplay positions", %{project: project} do
      {:ok, s1} = Screenplays.create_screenplay(project, %{name: "A"})
      {:ok, s2} = Screenplays.create_screenplay(project, %{name: "B"})
      {:ok, s3} = Screenplays.create_screenplay(project, %{name: "C"})

      {:ok, result} =
        Screenplays.reorder_screenplays(project.id, nil, [s3.id, s1.id, s2.id])

      ids = Enum.map(result, & &1.id)
      assert ids == [s3.id, s1.id, s2.id]
    end
  end

  describe "move_screenplay_to_position/3" do
    setup :setup_project

    test "moves screenplay to a new parent", %{project: project} do
      {:ok, parent} = Screenplays.create_screenplay(project, %{name: "Parent"})
      {:ok, child} = Screenplays.create_screenplay(project, %{name: "Child"})

      {:ok, moved} = Screenplays.move_screenplay_to_position(child, parent.id, 0)

      assert moved.parent_id == parent.id
      assert moved.position == 0
    end
  end

  # ===========================================================================
  # Element CRUD through facade
  # ===========================================================================

  describe "list_elements/1" do
    setup :setup_project

    test "returns elements ordered by position", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Script"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "action", content: "One"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "action", content: "Two"})

      elements = Screenplays.list_elements(sp.id)

      assert length(elements) == 2
      assert Enum.map(elements, & &1.position) == [0, 1]
    end
  end

  describe "create_element/2" do
    setup :setup_project

    test "creates element at end of screenplay", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Script"})

      {:ok, e1} = Screenplays.create_element(sp, %{type: "scene_heading", content: "INT."})
      {:ok, e2} = Screenplays.create_element(sp, %{type: "action", content: "Walk."})

      assert e1.position == 0
      assert e2.position == 1
    end
  end

  describe "update_element/2" do
    setup :setup_project

    test "updates element content", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Script"})
      {:ok, el} = Screenplays.create_element(sp, %{type: "action", content: "Original"})

      {:ok, updated} = Screenplays.update_element(el, %{content: "Updated"})

      assert updated.content == "Updated"
    end
  end

  describe "delete_element/1" do
    setup :setup_project

    test "deletes element and compacts positions", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Script"})
      {:ok, e1} = Screenplays.create_element(sp, %{type: "action", content: "One"})
      {:ok, _e2} = Screenplays.create_element(sp, %{type: "action", content: "Two"})
      {:ok, _e3} = Screenplays.create_element(sp, %{type: "action", content: "Three"})

      {:ok, _} = Screenplays.delete_element(e1)

      elements = Screenplays.list_elements(sp.id)
      assert length(elements) == 2
      assert Enum.map(elements, & &1.position) == [0, 1]
    end
  end

  # ===========================================================================
  # Element Grouping through facade
  # ===========================================================================

  describe "compute_dialogue_groups/1" do
    test "groups character + dialogue elements" do
      elements = [
        %ScreenplayElement{id: 1, type: "character", content: "JOHN", position: 0},
        %ScreenplayElement{id: 2, type: "dialogue", content: "Hello", position: 1}
      ]

      result = Screenplays.compute_dialogue_groups(elements)

      assert length(result) == 2
      [{_el1, group1}, {_el2, group2}] = result
      assert group1 != nil
      assert group1 == group2
    end

    test "returns empty list for empty input" do
      assert Screenplays.compute_dialogue_groups([]) == []
    end
  end

  describe "group_elements/1" do
    test "creates dialogue groups from adjacent character/dialogue", %{} do
      elements = [
        %ScreenplayElement{id: 1, type: "scene_heading", content: "INT.", position: 0},
        %ScreenplayElement{id: 2, type: "character", content: "JOHN", position: 1},
        %ScreenplayElement{id: 3, type: "dialogue", content: "Hi", position: 2}
      ]

      groups = Screenplays.group_elements(elements)

      assert length(groups) == 2
      assert Enum.at(groups, 0).type == :scene_heading
      assert Enum.at(groups, 1).type == :dialogue_group
    end

    test "returns empty list for empty input" do
      assert Screenplays.group_elements([]) == []
    end
  end

  # ===========================================================================
  # Auto-Detection through facade
  # ===========================================================================

  describe "detect_type/1" do
    test "detects scene heading" do
      assert Screenplays.detect_type("INT. LIVING ROOM - DAY") == "scene_heading"
      assert Screenplays.detect_type("EXT. FOREST - NIGHT") == "scene_heading"
    end

    test "detects transition" do
      assert Screenplays.detect_type("CUT TO:") == "transition"
      assert Screenplays.detect_type("FADE IN:") == "transition"
    end

    test "detects character" do
      assert Screenplays.detect_type("JOHN") == "character"
      assert Screenplays.detect_type("MARY (V.O.)") == "character"
    end

    test "detects parenthetical" do
      assert Screenplays.detect_type("(whispering)") == "parenthetical"
    end

    test "returns nil for plain text" do
      assert Screenplays.detect_type("He walks away.") == nil
    end

    test "returns nil for empty string" do
      assert Screenplays.detect_type("") == nil
    end
  end

  # ===========================================================================
  # ContentUtils through facade
  # ===========================================================================

  describe "content_strip_html/1" do
    test "strips HTML tags" do
      assert Screenplays.content_strip_html("<p>Hello <strong>world</strong></p>") ==
               "Hello world"
    end

    test "handles nil" do
      assert Screenplays.content_strip_html(nil) == ""
    end

    test "handles empty string" do
      assert Screenplays.content_strip_html("") == ""
    end

    test "handles plain text" do
      assert Screenplays.content_strip_html("plain text") == "plain text"
    end
  end

  describe "content_sanitize_html/1" do
    test "keeps safe tags" do
      assert Screenplays.content_sanitize_html("<p>Hello</p>") == "<p>Hello</p>"
    end

    test "strips unsafe tags" do
      result = Screenplays.content_sanitize_html("<script>alert('xss')</script><p>Safe</p>")
      assert result =~ "Safe"
      refute result =~ "<script>"
    end

    test "handles nil" do
      assert Screenplays.content_sanitize_html(nil) == ""
    end

    test "handles empty string" do
      assert Screenplays.content_sanitize_html("") == ""
    end
  end

  # ===========================================================================
  # CharacterExtension through facade
  # ===========================================================================

  describe "character_base_name/1" do
    test "extracts base name without extensions" do
      assert Screenplays.character_base_name("JAIME (V.O.)") == "JAIME"
    end

    test "returns name when no extensions" do
      assert Screenplays.character_base_name("JAIME") == "JAIME"
    end

    test "handles nil" do
      assert Screenplays.character_base_name(nil) == ""
    end

    test "handles multiple extensions" do
      assert Screenplays.character_base_name("JAIME (V.O.) (CONT'D)") == "JAIME"
    end
  end

  # ===========================================================================
  # TiptapSerialization through facade
  # ===========================================================================

  describe "elements_to_doc/1" do
    test "converts elements to TipTap doc" do
      elements = [
        %ScreenplayElement{
          id: 1,
          type: "action",
          content: "Hello world",
          data: %{},
          position: 0
        }
      ]

      result = Screenplays.elements_to_doc(elements)

      assert result["type"] == "doc"
      assert length(result["content"]) == 1
      assert hd(result["content"])["type"] == "action"
    end

    test "returns doc with empty action for empty list" do
      result = Screenplays.elements_to_doc([])

      assert result["type"] == "doc"
      assert length(result["content"]) == 1
      assert hd(result["content"])["type"] == "action"
    end
  end

  # ===========================================================================
  # replace_elements_from_fountain/3
  # ===========================================================================

  describe "replace_elements_from_fountain/3" do
    setup :setup_project

    test "replaces existing elements with new ones", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Fountain Import"})

      {:ok, old1} =
        Screenplays.create_element(sp, %{type: "action", content: "Old content"})

      {:ok, old2} =
        Screenplays.create_element(sp, %{type: "dialogue", content: "Old dialogue"})

      existing = [old1, old2]

      parsed = [
        %{type: "scene_heading", content: "INT. NEW SCENE - DAY"},
        %{type: "character", content: "JANE"},
        %{type: "dialogue", content: "New dialogue."}
      ]

      {:ok, %{create_imported: new_elements}} =
        Screenplays.replace_elements_from_fountain(sp, existing, parsed)

      assert length(new_elements) == 3
      assert hd(new_elements).type == "scene_heading"

      # Old elements should be gone
      elements = Screenplays.list_elements(sp.id)
      old_ids = Enum.map(existing, & &1.id)
      new_ids = Enum.map(elements, & &1.id)
      assert Enum.all?(old_ids, &(&1 not in new_ids))
    end

    test "handles empty existing elements", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Empty Start"})

      parsed = [
        %{type: "action", content: "New content"}
      ]

      {:ok, %{create_imported: new_elements}} =
        Screenplays.replace_elements_from_fountain(sp, [], parsed)

      assert length(new_elements) == 1
    end

    test "handles empty parsed elements", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Clear All"})

      {:ok, old} = Screenplays.create_element(sp, %{type: "action", content: "Old"})

      {:ok, %{create_imported: new_elements}} =
        Screenplays.replace_elements_from_fountain(sp, [old], [])

      assert new_elements == []

      # Old element should be deleted
      elements = Screenplays.list_elements(sp.id)
      assert elements == []
    end
  end

  # ===========================================================================
  # Export/Import helpers through facade
  # ===========================================================================

  describe "list_screenplays_for_export/1" do
    setup :setup_project

    test "returns screenplays with elements", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Export"})
      {:ok, _} = Screenplays.create_element(sp, %{type: "action", content: "Content"})

      result = Screenplays.list_screenplays_for_export(project.id)

      assert length(result) == 1
      assert hd(result).name == "Export"
      assert length(hd(result).elements) == 1
    end
  end

  describe "count_screenplays/1" do
    setup :setup_project

    test "counts non-deleted screenplays", %{project: project} do
      {:ok, _} = Screenplays.create_screenplay(project, %{name: "One"})
      {:ok, sp2} = Screenplays.create_screenplay(project, %{name: "Two"})
      {:ok, _} = Screenplays.delete_screenplay(sp2)

      assert Screenplays.count_screenplays(project.id) == 1
    end

    test "returns 0 for empty project", %{project: project} do
      assert Screenplays.count_screenplays(project.id) == 0
    end
  end

  describe "list_screenplay_shortcuts/1" do
    setup :setup_project

    test "returns shortcuts as MapSet", %{project: project} do
      {:ok, _} = Screenplays.create_screenplay(project, %{name: "First Scene"})
      {:ok, _} = Screenplays.create_screenplay(project, %{name: "Second Scene"})

      result = Screenplays.list_screenplay_shortcuts(project.id)

      assert %MapSet{} = result
      assert MapSet.member?(result, "first-scene")
      assert MapSet.member?(result, "second-scene")
    end
  end

  describe "detect_screenplay_shortcut_conflicts/2" do
    setup :setup_project

    test "detects conflicts", %{project: project} do
      {:ok, _} = Screenplays.create_screenplay(project, %{name: "Existing"})

      conflicts =
        Screenplays.detect_screenplay_shortcut_conflicts(project.id, ["existing", "new-one"])

      assert "existing" in conflicts
      refute "new-one" in conflicts
    end

    test "returns empty for no conflicts", %{project: project} do
      assert Screenplays.detect_screenplay_shortcut_conflicts(project.id, ["none"]) == []
    end
  end

  describe "soft_delete_screenplay_by_shortcut/2" do
    setup :setup_project

    test "soft-deletes by shortcut", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Target"})

      {count, _} = Screenplays.soft_delete_screenplay_by_shortcut(project.id, sp.shortcut)

      assert count == 1
      refute Screenplays.screenplay_exists?(project.id, sp.id)
    end
  end

  describe "import_screenplay/3" do
    setup :setup_project

    test "imports screenplay with raw attrs", %{project: project} do
      {:ok, sp} =
        Screenplays.import_screenplay(project.id, %{name: "Imported", shortcut: "imported"})

      assert sp.name == "Imported"
      assert sp.project_id == project.id
    end

    test "accepts extra_changes", %{project: project} do
      {:ok, sp} =
        Screenplays.import_screenplay(project.id, %{name: "Extras", shortcut: "extras"}, %{
          draft_label: "v1"
        })

      assert sp.draft_label == "v1"
    end
  end

  describe "import_element/3" do
    setup :setup_project

    test "imports element with raw attrs", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Host"})

      {:ok, el} =
        Screenplays.import_element(sp.id, %{type: "action", content: "Test", position: 0})

      assert el.type == "action"
      assert el.screenplay_id == sp.id
    end
  end

  describe "link_screenplay_import_refs/2" do
    setup :setup_project

    test "links parent_id after import", %{project: project} do
      {:ok, parent} = Screenplays.create_screenplay(project, %{name: "Parent"})
      {:ok, child} = Screenplays.create_screenplay(project, %{name: "Child"})

      result = Screenplays.link_screenplay_import_refs(child, %{parent_id: parent.id})

      assert result.parent_id == parent.id
    end

    test "returns :ok for empty changes", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "No Changes"})
      assert Screenplays.link_screenplay_import_refs(sp, %{}) == :ok
    end
  end

  # ===========================================================================
  # Fountain export/import through facade
  # ===========================================================================

  describe "export_fountain/1" do
    test "exports elements to Fountain format" do
      elements = [
        %ScreenplayElement{
          id: 1,
          type: "scene_heading",
          content: "INT. OFFICE - DAY",
          data: %{},
          position: 0,
          depth: 0,
          branch: nil
        },
        %ScreenplayElement{
          id: 2,
          type: "action",
          content: "John walks in.",
          data: %{},
          position: 1,
          depth: 0,
          branch: nil
        }
      ]

      result = Screenplays.export_fountain(elements)

      assert is_binary(result)
      assert result =~ "INT. OFFICE - DAY"
      assert result =~ "John walks in."
    end
  end

  describe "parse_fountain/1" do
    test "parses Fountain text into element attrs" do
      text = """
      INT. OFFICE - DAY

      John walks in.

      JOHN
      Hello there.
      """

      result = Screenplays.parse_fountain(text)

      assert is_list(result)
      types = Enum.map(result, & &1.type)
      assert "scene_heading" in types
    end
  end

  # ===========================================================================
  # list_deleted_screenplays through facade
  # ===========================================================================

  describe "list_deleted_screenplays/1" do
    setup :setup_project

    test "returns deleted screenplays", %{project: project} do
      {:ok, sp} = Screenplays.create_screenplay(project, %{name: "Trashed"})
      {:ok, _} = Screenplays.delete_screenplay(sp)

      result = Screenplays.list_deleted_screenplays(project.id)
      ids = Enum.map(result, & &1.id)

      assert sp.id in ids
    end

    test "returns empty when nothing is deleted", %{project: project} do
      {:ok, _} = Screenplays.create_screenplay(project, %{name: "Active"})
      assert Screenplays.list_deleted_screenplays(project.id) == []
    end
  end
end
