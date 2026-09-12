defmodule Storyarn.Projects.Assets.Queries.ReferenceTargets do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Memberships

  @max_id 9_223_372_036_854_775_807

  def query(%{user: %{id: user_id}} = scope, project_id)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id in 1..@max_id do
    case Memberships.authorize(scope, project_id, :view) do
      {:ok, _project, _membership} ->
        {:ok,
         from(item in Asset,
           where: item.project_id == ^project_id and is_nil(item.deleted_at),
           select: %{
             id: item.id,
             name: fragment("left(?, 240)", item.filename),
             name_digest: fragment("md5(?)", item.filename),
             content_type: item.content_type,
             size: item.size,
             blob_hash: item.blob_hash,
             inserted_at: item.inserted_at,
             search_text: item.filename
           }
         )}

      _unavailable ->
        {:error, :not_found}
    end
  end

  def query(_scope, _project_id), do: {:error, :not_found}
end
