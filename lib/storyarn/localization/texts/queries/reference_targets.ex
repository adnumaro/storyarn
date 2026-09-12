defmodule Storyarn.Localization.Texts.Queries.ReferenceTargets do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects

  @max_id 9_223_372_036_854_775_807

  def query(%{user: %{id: user_id}} = scope, project_id)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id in 1..@max_id do
    case Projects.authorize(scope, project_id, :view) do
      {:ok, _project, _membership} ->
        {:ok,
         from(item in LocalizedText,
           where: item.project_id == ^project_id and is_nil(item.archived_at),
           select: %{
             id: item.id,
             name: fragment("left(?, 240)", item.source_text),
             locale_code: item.locale_code,
             source_type: item.source_type,
             source_id: item.source_id,
             source_field: item.source_field,
             source_text: fragment("left(?, 2001)", item.source_text),
             translated_text: fragment("left(?, 2001)", item.translated_text),
             source_digest: fragment("md5(coalesce(?, ''))", item.source_text),
             translated_digest: fragment("md5(coalesce(?, ''))", item.translated_text),
             source_text_bytes: fragment("octet_length(coalesce(?, ''))", item.source_text),
             translated_text_bytes: fragment("octet_length(coalesce(?, ''))", item.translated_text),
             status: item.status,
             inserted_at: item.inserted_at,
             search_text: fragment("concat_ws(' ', ?, ?, ?)", item.source_text, item.translated_text, item.locale_code)
           }
         )}

      _unavailable ->
        {:error, :not_found}
    end
  end

  def query(_scope, _project_id), do: {:error, :not_found}
end
