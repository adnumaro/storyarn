defmodule Storyarn.Screenplays.ScreenplayQueriesTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Screenplays.{Screenplay, ScreenplayQueries}

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project}
  end

  describe "get_with_elements/1" do
    setup :setup_project

    test "preloads elements in position order", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "character", content: "JAIME", position: 1})
      element_fixture(screenplay, %{type: "scene_heading", content: "INT.", position: 0})

      result = ScreenplayQueries.get_with_elements(screenplay.id)

      assert result.id == screenplay.id
      assert length(result.elements) == 2
      assert hd(result.elements).type == "scene_heading"
      assert List.last(result.elements).type == "character"
    end

    test "returns nil for deleted screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)

      screenplay
      |> Screenplay.delete_changeset()
      |> Repo.update!()

      assert ScreenplayQueries.get_with_elements(screenplay.id) == nil
    end
  end

  describe "count_elements/1" do
    setup :setup_project

    test "returns correct count", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading"})
      element_fixture(screenplay, %{type: "action"})
      element_fixture(screenplay, %{type: "character"})

      assert ScreenplayQueries.count_elements(screenplay.id) == 3
    end

    test "returns 0 for empty screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)
      assert ScreenplayQueries.count_elements(screenplay.id) == 0
    end
  end

  describe "list_drafts/1" do
    setup :setup_project

    test "returns drafts of a screenplay", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft A"})
        |> Repo.insert()

      result = ScreenplayQueries.list_drafts(original.id)
      assert length(result) == 1
      assert hd(result).id == draft.id
    end

    test "excludes deleted drafts", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft A"})
        |> Repo.insert()

      draft |> Screenplay.delete_changeset() |> Repo.update!()

      assert ScreenplayQueries.list_drafts(original.id) == []
    end

    test "returns empty for screenplay with no drafts", %{project: project} do
      original = screenplay_fixture(project)
      assert ScreenplayQueries.list_drafts(original.id) == []
    end
  end

  # =============================================================================
  # query_screenplay_element_backlinks/3
  # =============================================================================

  describe "query_screenplay_element_backlinks/3" do
    setup :setup_project

    test "returns empty list when no backlinks exist", %{project: project} do
      result =
        ScreenplayQueries.query_screenplay_element_backlinks("sheet", 999_999, project.id)

      assert result == []
    end

    test "returns backlinks with source_info when references exist", %{project: project} do
      import Storyarn.SheetsFixtures

      screenplay = screenplay_fixture(project, %{name: "Test Screenplay"})
      element = element_fixture(screenplay, %{type: "character", content: "JAIME"})
      sheet = sheet_fixture(project, %{name: "MC Jaime"})

      # Create an entity reference from the screenplay element to the sheet
      alias Storyarn.Sheets.EntityReference

      {:ok, _ref} =
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "screenplay_element",
          source_id: element.id,
          target_type: "sheet",
          target_id: sheet.id,
          context: "character_name"
        })
        |> Repo.insert()

      result =
        ScreenplayQueries.query_screenplay_element_backlinks("sheet", sheet.id, project.id)

      assert length(result) == 1
      backlink = hd(result)
      assert backlink.source_type == "screenplay_element"
      assert backlink.source_id == element.id
      assert backlink.source_info.type == :screenplay
      assert backlink.source_info.screenplay_id == screenplay.id
      assert backlink.source_info.screenplay_name == "Test Screenplay"
      assert backlink.source_info.element_type == "character"
    end

    test "excludes backlinks from deleted screenplays", %{project: project} do
      import Storyarn.SheetsFixtures

      screenplay = screenplay_fixture(project, %{name: "Deleted Screenplay"})
      element = element_fixture(screenplay, %{type: "action"})
      sheet = sheet_fixture(project)

      alias Storyarn.Sheets.EntityReference

      {:ok, _ref} =
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "screenplay_element",
          source_id: element.id,
          target_type: "sheet",
          target_id: sheet.id,
          context: "reference"
        })
        |> Repo.insert()

      # Soft-delete the screenplay
      screenplay |> Screenplay.delete_changeset() |> Repo.update!()

      result =
        ScreenplayQueries.query_screenplay_element_backlinks("sheet", sheet.id, project.id)

      assert result == []
    end

    test "filters by project_id", %{project: project} do
      import Storyarn.SheetsFixtures

      # Create another project
      other_user = user_fixture()
      other_project = project_fixture(other_user)

      screenplay = screenplay_fixture(other_project, %{name: "Other Project Screenplay"})
      element = element_fixture(screenplay, %{type: "action"})
      sheet = sheet_fixture(project)

      alias Storyarn.Sheets.EntityReference

      {:ok, _ref} =
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "screenplay_element",
          source_id: element.id,
          target_type: "sheet",
          target_id: sheet.id,
          context: "reference"
        })
        |> Repo.insert()

      # Should not find backlinks from other project
      result =
        ScreenplayQueries.query_screenplay_element_backlinks("sheet", sheet.id, project.id)

      assert result == []
    end

    test "returns all matching backlinks", %{project: project} do
      import Storyarn.SheetsFixtures

      screenplay = screenplay_fixture(project)
      elem1 = element_fixture(screenplay, %{type: "character", content: "A"})
      elem2 = element_fixture(screenplay, %{type: "character", content: "B"})
      sheet = sheet_fixture(project)

      alias Storyarn.Sheets.EntityReference

      {:ok, _} =
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "screenplay_element",
          source_id: elem1.id,
          target_type: "sheet",
          target_id: sheet.id,
          context: "ref1"
        })
        |> Repo.insert()

      {:ok, _} =
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "screenplay_element",
          source_id: elem2.id,
          target_type: "sheet",
          target_id: sheet.id,
          context: "ref2"
        })
        |> Repo.insert()

      result =
        ScreenplayQueries.query_screenplay_element_backlinks("sheet", sheet.id, project.id)

      assert length(result) == 2
      source_ids = Enum.map(result, & &1.source_id)
      assert elem1.id in source_ids
      assert elem2.id in source_ids
    end
  end
end
