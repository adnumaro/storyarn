defmodule StoryarnWeb.Live.Shared.PickerSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.Live.Shared.PickerSearch

  describe "asset_options/3" do
    test "returns a bounded page and reports more image results" do
      user = user_fixture()
      project = project_fixture(user)

      for idx <- 1..3 do
        image_asset_fixture(project, user, %{filename: "scene_#{idx}.png"})
      end

      audio_asset_fixture(project, user, %{filename: "scene_theme.mp3"})

      {results, has_more} = PickerSearch.asset_options(project.id, "image", limit: 2)

      assert length(results) == 2
      assert has_more
      assert Enum.all?(results, &String.starts_with?(&1.content_type, "image/"))
    end

    test "keeps a selected asset outside the first page" do
      user = user_fixture()
      project = project_fixture(user)

      selected = image_asset_fixture(project, user, %{filename: "selected.png"})
      selected = selected |> Ecto.Changeset.change(inserted_at: ~U[2020-01-01 00:00:00Z]) |> Repo.update!()

      for idx <- 1..3 do
        image_asset_fixture(project, user, %{filename: "newer_#{idx}.png"})
      end

      {results, has_more} = PickerSearch.asset_options(project.id, "image", limit: 1, selected_id: selected.id)

      assert Enum.any?(results, &(&1.id == selected.id))
      assert length(results) == 2
      assert has_more
    end
  end

  describe "sheet_options/2" do
    test "searches sheets by query with a bounded page" do
      project = project_fixture()
      matching = sheet_fixture(project, %{name: "Hero Sheet"})
      _other = sheet_fixture(project, %{name: "Villain Sheet"})

      {results, has_more} = PickerSearch.sheet_options(project.id, query: "hero", limit: 1)

      assert results == [%{id: matching.id, name: matching.name}]
      refute has_more
    end

    test "keeps a selected sheet outside the first page" do
      project = project_fixture()
      selected = sheet_fixture(project, %{name: "Selected Sheet"})
      selected = selected |> Ecto.Changeset.change(updated_at: ~U[2020-01-01 00:00:00Z]) |> Repo.update!()

      for idx <- 1..3 do
        sheet_fixture(project, %{name: "Newer Sheet #{idx}"})
      end

      {results, has_more} = PickerSearch.sheet_options(project.id, limit: 1, selected_id: selected.id)

      assert Enum.any?(results, &(&1.id == selected.id))
      assert length(results) == 2
      assert has_more
    end
  end

  describe "flow_options/2" do
    test "searches flows by query with a bounded page" do
      project = project_fixture()
      matching = flow_fixture(project, %{name: "Intro Flow"})
      _other = flow_fixture(project, %{name: "Outro Flow"})

      {results, has_more} = PickerSearch.flow_options(project.id, query: "intro", limit: 1)

      assert results == [%{id: matching.id, name: matching.name}]
      refute has_more
    end
  end
end
