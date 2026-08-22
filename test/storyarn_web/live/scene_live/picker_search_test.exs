defmodule StoryarnWeb.SceneLive.PickerSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias StoryarnWeb.SceneLive.PickerSearch

  test "serializes Scene-owned asset options with authorized media URLs" do
    user = user_fixture()
    project = project_fixture(user)
    optimized = image_asset_fixture(project, user, %{filename: "optimized.webp"})

    asset =
      image_asset_fixture(project, user, %{
        filename: "scene-portrait.png",
        metadata: %{"web_asset_id" => optimized.id}
      })

    assert PickerSearch.asset_options(project.id, "image", query: "portrait", limit: 10) ==
             {[
                %{
                  id: asset.id,
                  filename: "scene-portrait.png",
                  content_type: asset.content_type,
                  url: "/media/assets/#{optimized.id}"
                }
              ], false}
  end
end
