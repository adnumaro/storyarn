defmodule StoryarnWeb.FlowLive.PickerSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias StoryarnWeb.FlowLive.PickerSearch

  test "serializes Flow-owned asset options with authorized media URLs" do
    user = user_fixture()
    project = project_fixture(user)
    optimized = image_asset_fixture(project, user, %{filename: "optimized.webp"})

    asset =
      image_asset_fixture(project, user, %{
        filename: "portrait.png",
        metadata: %{"web_asset_id" => optimized.id}
      })

    assert PickerSearch.asset_options(project.id, "image", query: "portrait", limit: 10) ==
             {[
                %{
                  id: asset.id,
                  filename: "portrait.png",
                  content_type: asset.content_type,
                  url: "/media/assets/#{optimized.id}"
                }
              ], false}
  end

  test "searches Flow options without the shared cross-tool picker" do
    project = project_fixture()
    matching = flow_fixture(project, %{name: "Intro Flow"})
    _other = flow_fixture(project, %{name: "Outro Flow"})

    assert PickerSearch.flow_options(project.id, query: "intro", limit: 1) ==
             {[%{id: matching.id, name: matching.name}], false}
  end

  test "returns the Flow-owned variable search projection without reshaping it" do
    variables = [
      %{sheet_shortcut: "hero", variable_name: "health", label: "Hero health"},
      %{sheet_shortcut: "world", variable_name: "weather", label: "World weather"}
    ]

    assert PickerSearch.variable_options(variables, query: "hero", limit: 10) ==
             {[%{id: "hero.health", name: "Hero health"}], false}
  end
end
