defmodule Storyarn.Scenes.Assets.Queries.CatalogTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Repo
  alias Storyarn.Scenes

  test "reads active image identities and records through the Scene-owned projection" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)
    active = image_asset_fixture(project, user, %{filename: "active-scene.png"})
    deleted = image_asset_fixture(project, user, %{filename: "deleted-scene.png"})
    _audio = audio_asset_fixture(project, user, %{filename: "scene-audio.mp3"})
    foreign = image_asset_fixture(other_project, user, %{filename: "foreign-scene.png"})

    assert {:ok, _deleted} = Assets.delete_asset(deleted)

    assert Scenes.list_image_asset_ids(project.id) == [active.id]
    assert Scenes.get_asset(project.id, active.id).id == active.id
    assert Scenes.get_asset(project.id, deleted.id) == nil
    assert Scenes.get_asset(project.id, foreign.id) == nil
    assert Scenes.get_asset(other_project.id, foreign.id).id == foreign.id
    assert Scenes.list_image_asset_ids(-1) == []
  end

  test "searches active assets by project, media kind and filename" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)
    matching = image_asset_fixture(project, user, %{filename: "scene-hero.png"})
    deleted = image_asset_fixture(project, user, %{filename: "scene-deleted.png"})
    _audio = audio_asset_fixture(project, user, %{filename: "scene-theme.mp3"})
    _foreign = image_asset_fixture(other_project, user, %{filename: "scene-foreign.png"})

    assert {:ok, _deleted} = Assets.delete_asset(deleted)

    assert Scenes.search_asset_options(project.id, "image", query: "scene", limit: 10) ==
             {[
                %{
                  id: matching.id,
                  filename: matching.filename,
                  content_type: matching.content_type,
                  metadata: matching.metadata
                }
              ], false}
  end

  test "retains a selected asset outside the first page" do
    user = user_fixture()
    project = project_fixture(user)
    selected = image_asset_fixture(project, user, %{filename: "selected.png"})

    Repo.update_all(
      from(asset in Asset, where: asset.id == ^selected.id),
      set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
    )

    for index <- 1..3 do
      image_asset_fixture(project, user, %{filename: "newer-#{index}.png"})
    end

    {results, has_more} =
      Scenes.search_asset_options(project.id, "image", limit: 1, selected_id: selected.id)

    assert has_more
    assert length(results) == 2
    assert Enum.any?(results, &(&1.id == selected.id))
  end
end
