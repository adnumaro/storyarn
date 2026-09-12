defmodule Storyarn.Sheets.Editor.Queries.ReferenceTargets do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Projects
  alias Storyarn.Sheets.Sheet

  @max_id 9_223_372_036_854_775_807

  def query(%{user: %{id: user_id}} = scope, project_id)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id in 1..@max_id do
    case Projects.authorize(scope, project_id, :view) do
      {:ok, _project, _membership} ->
        {:ok,
         from(item in Sheet,
           where: item.project_id == ^project_id and is_nil(item.deleted_at),
           select: %{
             id: item.id,
             name: fragment("left(?, 240)", item.name),
             name_digest: fragment("md5(?)", item.name),
             shortcut: item.shortcut,
             description: fragment("left(?, 2001)", item.description),
             description_digest: fragment("md5(coalesce(?, ''))", item.description),
             description_bytes: fragment("octet_length(coalesce(?, ''))", item.description),
             color: item.color,
             inserted_at: item.inserted_at,
             search_text: fragment("concat_ws(' ', ?, ?)", item.name, item.shortcut)
           }
         )}

      _unavailable ->
        {:error, :not_found}
    end
  end

  def query(_scope, _project_id), do: {:error, :not_found}
end
