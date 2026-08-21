defmodule Storyarn.Flows.PlayerCatalog do
  @moduledoc """
  Consumer-owned speaker catalog for the Flow player.

  In the Flows domain, a Sheet referenced by a dialogue node acts as a
  speaker. This read model maps the shared persistence tables directly and
  returns only the speaker and avatar data required by the runtime.
  """

  import Ecto.Query

  alias Storyarn.Flows.Persistence.SheetRecord
  alias Storyarn.Repo

  @type media_ref :: %{id: integer(), filename: String.t() | nil}
  @type avatar :: %{
          id: integer(),
          name: String.t() | nil,
          position: integer(),
          is_default: boolean(),
          asset: media_ref() | nil
        }
  @type speaker :: %{
          id: integer(),
          name: String.t() | nil,
          color: String.t() | nil,
          avatars: [avatar()]
        }

  @doc "Loads the active speakers required by the Flow player."
  @spec load_speakers(integer()) :: [speaker()]
  def load_speakers(project_id) do
    from(sheet in SheetRecord,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      order_by: [asc: sheet.position, asc: sheet.name],
      preload: [avatars: :asset]
    )
    |> Repo.all()
    |> Enum.map(&to_speaker/1)
  end

  defp to_speaker(sheet) do
    %{
      id: sheet.id,
      name: sheet.name,
      color: sheet.color,
      avatars:
        sheet.avatars
        |> Enum.sort_by(& &1.position)
        |> Enum.map(&to_avatar/1)
    }
  end

  defp to_avatar(avatar) do
    %{
      id: avatar.id,
      name: avatar.name,
      position: avatar.position,
      is_default: avatar.is_default,
      asset: media_ref(avatar.asset)
    }
  end

  defp media_ref(nil), do: nil

  defp media_ref(asset) do
    id =
      case asset.metadata do
        %{"web_asset_id" => web_asset_id} when is_integer(web_asset_id) -> web_asset_id
        _metadata -> asset.id
      end

    %{id: id, filename: asset.filename}
  end
end
