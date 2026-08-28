defmodule Storyarn.Localization.Texts.Queries.BatchTranslation do
  @moduledoc "Stable-cursor queries used by batch translation jobs."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo

  def list_texts_for_batch_translation(project_id, opts \\ []) do
    from(t in LocalizedText, where: t.project_id == ^project_id, order_by: [asc: t.id])
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_after_id(opts[:after_id])
    |> maybe_filter_max_id(opts[:max_id])
    |> maybe_paginate(opts[:limit])
    |> Repo.all()
  end

  def max_text_id_for_batch_translation(project_id, opts \\ []) do
    from(t in LocalizedText, where: t.project_id == ^project_id, select: max(t.id))
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> Repo.one()
  end

  defp maybe_filter_locale(query, nil), do: query
  defp maybe_filter_locale(query, locale), do: where(query, [t], t.locale_code == ^locale)
  defp maybe_filter_archived(query, true), do: query
  defp maybe_filter_archived(query, _), do: where(query, [t], is_nil(t.archived_at))
  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)
  defp maybe_filter_source_type(query, nil), do: query
  defp maybe_filter_source_type(query, type), do: where(query, [t], t.source_type == ^type)
  defp maybe_filter_after_id(query, nil), do: query
  defp maybe_filter_after_id(query, id), do: where(query, [t], t.id > ^id)
  defp maybe_filter_max_id(query, nil), do: query
  defp maybe_filter_max_id(query, id), do: where(query, [t], t.id <= ^id)
  defp maybe_paginate(query, nil), do: query
  defp maybe_paginate(query, limit), do: limit(query, ^limit)
end
