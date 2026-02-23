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
end
