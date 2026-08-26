defmodule Storyarn.Localization.Exchange.Commands.ImportCsv do
  @moduledoc false

  alias Storyarn.Localization.Exchange.Rules.Csv
  alias Storyarn.Localization.Texts

  @valid_statuses ~w(pending draft in_progress review final)

  @spec import(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def import(project_id, csv_content) do
    case Csv.records(csv_content) do
      [header_line | data_lines] ->
        headers = Csv.fields(header_line)
        id_col = Csv.column_index(headers, "ID")
        translation_col = Csv.column_index(headers, "Translation")
        status_col = Csv.column_index(headers, "Status")
        source_hash_col = Csv.column_index(headers, "Source Hash")

        if id_col do
          {updated, skipped, errors} =
            data_lines
            |> Enum.with_index(2)
            |> Enum.reduce(
              {0, 0, []},
              &reduce_row(&1, &2, project_id, id_col, translation_col, status_col, source_hash_col)
            )

          {:ok, %{updated: updated, skipped: skipped, errors: Enum.reverse(errors)}}
        else
          {:error, :missing_id_column}
        end

      _ ->
        {:error, :empty_file}
    end
  end

  defp reduce_row(
         {line, line_num},
         {updated, skipped, errors},
         project_id,
         id_col,
         translation_col,
         status_col,
         source_hash_col
       ) do
    fields = Csv.fields(line)
    id = Enum.at(fields, id_col)
    translation = if translation_col, do: Enum.at(fields, translation_col)
    status = if status_col, do: Enum.at(fields, status_col)
    source_hash = if source_hash_col, do: Enum.at(fields, source_hash_col)

    case import_row(project_id, id, translation, status, source_hash) do
      :ok -> {updated + 1, skipped, errors}
      :skip -> {updated, skipped + 1, errors}
      {:error, reason} -> {updated, skipped, [{line_num, reason} | errors]}
    end
  end

  defp import_row(project_id, id_string, translation, status, source_hash) do
    with {id, ""} <- Integer.parse(id_string || ""),
         text when not is_nil(text) <- Texts.get_text(project_id, id),
         :ok <- validate_source_hash(text, source_hash) do
      attrs = build_attrs(Csv.remove_spreadsheet_escape(translation), status)
      apply_attrs(text, attrs)
    else
      nil -> {:error, :text_not_found}
      {:error, reason} -> {:error, reason}
      :error -> {:error, :invalid_id}
      _ -> :skip
    end
  end

  defp build_attrs(translation, status) do
    %{}
    |> maybe_put_translation(translation)
    |> maybe_put_status(status)
  end

  defp maybe_put_translation(attrs, translation) when is_binary(translation) do
    if String.trim(translation) == "",
      do: attrs,
      else: Map.put(attrs, "translated_text", translation)
  end

  defp maybe_put_translation(attrs, _translation), do: attrs
  defp maybe_put_status(attrs, status) when status in @valid_statuses, do: Map.put(attrs, "status", status)
  defp maybe_put_status(attrs, _status), do: attrs

  defp apply_attrs(_text, attrs) when attrs == %{}, do: :skip

  defp apply_attrs(text, attrs) do
    case Texts.update_text(text, attrs) do
      {:ok, _text} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_source_hash(_text, nil), do: :ok
  defp validate_source_hash(_text, ""), do: :ok

  defp validate_source_hash(text, source_hash) do
    if String.trim(source_hash) == text.source_text_hash,
      do: :ok,
      else: {:error, :stale_source}
  end
end
