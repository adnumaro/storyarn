defmodule StoryarnWeb.SceneLive.FlowPresenter do
  @moduledoc false

  alias Storyarn.Scenes
  alias StoryarnWeb.PrivateMedia

  @doc "Builds the speaker projection consumed by the Scene exploration runtime."
  @spec speakers_map(integer()) :: map()
  def speakers_map(project_id) do
    project_id
    |> Scenes.list_all_sheets()
    |> Map.new(fn sheet ->
      avatars =
        sheet.avatars
        |> Enum.sort_by(& &1.position)
        |> Enum.map(fn avatar ->
          %{
            id: avatar.id,
            url: PrivateMedia.asset_url(avatar.asset),
            is_default: avatar.is_default
          }
        end)
        |> Enum.filter(& &1.url)

      default_avatar = Enum.find(avatars, & &1.is_default)

      {to_string(sheet.id),
       %{
         id: sheet.id,
         name: sheet.name,
         color: sheet.color,
         avatar_url: default_avatar && default_avatar.url,
         avatars: Enum.map(avatars, &Map.take(&1, [:id, :url]))
       }}
    end)
  end
end
