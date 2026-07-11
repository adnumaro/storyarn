defmodule Storyarn.Localization.ExportImport do
  @moduledoc false

  alias Storyarn.Localization.TextCrud

  # =============================================================================
  # Excel Export
  # =============================================================================

  @doc """
  Exports localized texts to an Excel (.xlsx) binary.

  Options:
  - `:locale_code` - Filter by locale (required)
  - `:status` - Filter by status
  - `:source_type` - Filter by source type
  - `:speaker_sheet_id` - Filter by speaker

  Returns `{:ok, binary}` with the .xlsx file content.
  """
  @spec export_xlsx(integer(), keyword()) :: {:ok, binary()}
  def export_xlsx(project_id, opts) do
    texts = TextCrud.list_texts(project_id, opts)

    header = [
      "ID",
      "Source Type",
      "Source ID",
      "Source Field",
      "Locale",
      "Source Hash",
      "Source Text",
      "Translation",
      "Status",
      "Word Count",
      "Machine Translated",
      "Translator Notes",
      "Reviewer Notes"
    ]

    rows =
      Enum.map(texts, fn text ->
        [
          text.id,
          text.source_type,
          text.source_id,
          text.source_field,
          text.locale_code,
          text.source_text_hash,
          spreadsheet_safe(strip_html(text.source_text)),
          spreadsheet_safe(strip_html(text.translated_text)),
          text.status,
          text.word_count || 0,
          if(text.machine_translated, do: "Yes", else: "No"),
          text.translator_notes || "",
          text.reviewer_notes || ""
        ]
      end)

    sheet = %Elixlsx.Sheet{
      name: "Translations",
      rows: [header | rows]
    }

    workbook = %Elixlsx.Workbook{sheets: [sheet]}
    {:ok, {_filename, binary}} = Elixlsx.write_to_memory(workbook, "translations.xlsx")
    {:ok, binary}
  end

  # =============================================================================
  # CSV Export
  # =============================================================================

  @doc """
  Exports localized texts to CSV format.

  Same options as `export_xlsx/2`.
  Returns `{:ok, csv_string}`.
  """
  @spec export_csv(integer(), keyword()) :: {:ok, String.t()}
  def export_csv(project_id, opts) do
    texts = TextCrud.list_texts(project_id, opts)

    header =
      "ID,Source Type,Source ID,Source Field,Locale,Source Hash,Source Text,Translation,Status,Word Count,Machine Translated"

    rows =
      Enum.map(texts, fn text ->
        Enum.join(
          [
            text.id,
            text.source_type,
            text.source_id,
            text.source_field,
            text.locale_code,
            text.source_text_hash,
            csv_escape(spreadsheet_safe(strip_html(text.source_text))),
            csv_escape(spreadsheet_safe(strip_html(text.translated_text))),
            text.status,
            text.word_count || 0,
            if(text.machine_translated, do: "Yes", else: "No")
          ],
          ","
        )
      end)

    csv = Enum.join([header | rows], "\n")
    {:ok, csv}
  end

  # =============================================================================
  # Import
  # =============================================================================

  @doc """
  Imports translations from CSV content.

  Expected columns: ID, Translation, Status (at minimum).
  The ID column must match existing localized_text IDs.

  Returns `{:ok, %{updated: N, skipped: M, errors: []}}`.
  """
  @spec import_csv(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def import_csv(project_id, csv_content) do
    lines = split_csv_records(csv_content)

    case lines do
      [header_line | data_lines] ->
        headers = parse_csv_line(header_line)
        id_col = find_column_index(headers, "ID")
        translation_col = find_column_index(headers, "Translation")
        status_col = find_column_index(headers, "Status")
        source_hash_col = find_column_index(headers, "Source Hash")

        if id_col do
          {updated, skipped, errors} =
            data_lines
            |> Enum.with_index(2)
            |> Enum.reduce(
              {0, 0, []},
              &reduce_csv_row(
                &1,
                &2,
                project_id,
                id_col,
                translation_col,
                status_col,
                source_hash_col
              )
            )

          {:ok, %{updated: updated, skipped: skipped, errors: Enum.reverse(errors)}}
        else
          {:error, :missing_id_column}
        end

      _ ->
        {:error, :empty_file}
    end
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp reduce_csv_row(
         {line, line_num},
         {upd, skip, errs},
         project_id,
         id_col,
         translation_col,
         status_col,
         source_hash_col
       ) do
    fields = parse_csv_line(line)
    id = Enum.at(fields, id_col)
    translation = if translation_col, do: Enum.at(fields, translation_col)
    status = if status_col, do: Enum.at(fields, status_col)
    source_hash = if source_hash_col, do: Enum.at(fields, source_hash_col)

    case import_row(project_id, id, translation, status, source_hash) do
      :ok -> {upd + 1, skip, errs}
      :skip -> {upd, skip + 1, errs}
      {:error, reason} -> {upd, skip, [{line_num, reason} | errs]}
    end
  end

  defp import_row(project_id, id_str, translation, status, source_hash) do
    with {id, ""} <- Integer.parse(id_str || ""),
         text when not is_nil(text) <- TextCrud.get_text(project_id, id),
         :ok <- validate_source_hash(text, source_hash) do
      attrs = build_import_attrs(remove_spreadsheet_escape(translation), status)
      apply_import_attrs(text, attrs)
    else
      nil -> {:error, :text_not_found}
      {:error, reason} -> {:error, reason}
      :error -> {:error, :invalid_id}
      _ -> :skip
    end
  end

  defp build_import_attrs(translation, status) do
    %{}
    |> maybe_put_translation(translation)
    |> maybe_put_status(status)
  end

  defp maybe_put_translation(attrs, translation) when is_binary(translation) do
    if String.trim(translation) == "",
      do: attrs,
      else: Map.put(attrs, "translated_text", translation)
  end

  defp maybe_put_translation(attrs, _), do: attrs

  defp maybe_put_status(attrs, status) when status in ~w(pending draft in_progress review final) do
    Map.put(attrs, "status", status)
  end

  defp maybe_put_status(attrs, _), do: attrs

  defp apply_import_attrs(_text, attrs) when attrs == %{}, do: :skip

  defp apply_import_attrs(text, attrs) do
    case TextCrud.update_text(text, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp strip_html(text), do: Storyarn.Shared.HtmlUtils.strip_html(text)

  defp validate_source_hash(_text, nil), do: :ok
  defp validate_source_hash(_text, ""), do: :ok

  defp validate_source_hash(text, source_hash) do
    if String.trim(source_hash) == text.source_text_hash, do: :ok, else: {:error, :stale_source}
  end

  defp spreadsheet_safe(nil), do: ""

  defp spreadsheet_safe(text) do
    if String.starts_with?(text, ["=", "+", "-", "@"]) do
      "'" <> text
    else
      text
    end
  end

  defp remove_spreadsheet_escape("'" <> rest = value) do
    if String.starts_with?(rest, ["=", "+", "-", "@"]) do
      rest
    else
      value
    end
  end

  defp remove_spreadsheet_escape(value), do: value

  defp csv_escape(nil), do: ""

  defp csv_escape(text) do
    if String.contains?(text, [",", "\"", "\n"]) do
      "\"" <> String.replace(text, "\"", "\"\"") <> "\""
    else
      text
    end
  end

  defp split_csv_records(content) do
    {records, current} = do_split_csv_records(content, [], [], false)

    [csv_record(current) | records]
    |> Enum.reverse()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp do_split_csv_records("", records, current, _quoted?), do: {records, current}

  defp do_split_csv_records("\"" <> rest, records, current, quoted?) do
    do_split_csv_records(rest, records, ["\"" | current], not quoted?)
  end

  defp do_split_csv_records("\n" <> rest, records, current, false) do
    do_split_csv_records(rest, [csv_record(current) | records], [], false)
  end

  defp do_split_csv_records(<<char::utf8, rest::binary>>, records, current, quoted?) do
    do_split_csv_records(rest, records, [<<char::utf8>> | current], quoted?)
  end

  defp csv_record(current) do
    current
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\r")
  end

  defp parse_csv_line(line) do
    # Simple CSV parser handling quoted fields
    line
    |> String.trim()
    |> do_parse_csv([], "")
    |> Enum.reverse()
  end

  defp do_parse_csv("", acc, current), do: [current | acc]
  defp do_parse_csv("," <> rest, acc, current), do: do_parse_csv(rest, [current | acc], "")

  defp do_parse_csv("\"" <> rest, acc, "") do
    # Start of quoted field
    {field, remaining} = parse_quoted_field(rest, "")
    do_parse_csv(remaining, acc, field)
  end

  defp do_parse_csv(<<char::utf8, rest::binary>>, acc, current) do
    do_parse_csv(rest, acc, current <> <<char::utf8>>)
  end

  defp parse_quoted_field("\"\"" <> rest, acc), do: parse_quoted_field(rest, acc <> "\"")
  defp parse_quoted_field("\"" <> rest, acc), do: {acc, rest}

  defp parse_quoted_field(<<char::utf8, rest::binary>>, acc), do: parse_quoted_field(rest, acc <> <<char::utf8>>)

  defp parse_quoted_field("", acc), do: {acc, ""}

  defp find_column_index(headers, name) do
    Enum.find_index(headers, &(String.downcase(String.trim(&1)) == String.downcase(name)))
  end
end
