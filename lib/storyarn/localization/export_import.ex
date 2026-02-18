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
          strip_html(text.source_text),
          strip_html(text.translated_text),
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
      "ID,Source Type,Source ID,Source Field,Locale,Source Text,Translation,Status,Word Count,Machine Translated"

    rows =
      Enum.map(texts, fn text ->
        [
          text.id,
          text.source_type,
          text.source_id,
          text.source_field,
          text.locale_code,
          csv_escape(strip_html(text.source_text)),
          csv_escape(strip_html(text.translated_text)),
          text.status,
          text.word_count || 0,
          if(text.machine_translated, do: "Yes", else: "No")
        ]
        |> Enum.join(",")
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
  @spec import_csv(String.t()) :: {:ok, map()} | {:error, term()}
  def import_csv(csv_content) do
    lines = String.split(csv_content, ~r/\r?\n/, trim: true)

    case lines do
      [header_line | data_lines] ->
        headers = parse_csv_line(header_line)
        id_col = find_column_index(headers, "ID")
        translation_col = find_column_index(headers, "Translation")
        status_col = find_column_index(headers, "Status")

        if id_col do
          {updated, skipped, errors} =
            data_lines
            |> Enum.with_index(2)
            |> Enum.reduce({0, 0, []}, &reduce_csv_row(&1, &2, id_col, translation_col, status_col))

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

  defp reduce_csv_row({line, line_num}, {upd, skip, errs}, id_col, translation_col, status_col) do
    fields = parse_csv_line(line)
    id = Enum.at(fields, id_col)
    translation = if translation_col, do: Enum.at(fields, translation_col)
    status = if status_col, do: Enum.at(fields, status_col)

    case import_row(id, translation, status) do
      :ok -> {upd + 1, skip, errs}
      :skip -> {upd, skip + 1, errs}
      {:error, reason} -> {upd, skip, [{line_num, reason} | errs]}
    end
  end

  defp import_row(id_str, translation, status) do
    with {id, ""} <- Integer.parse(id_str || ""),
         text when not is_nil(text) <- TextCrud.get_text(id) do
      attrs = build_import_attrs(translation, status)
      apply_import_attrs(text, attrs)
    else
      nil -> {:error, :text_not_found}
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
    if String.trim(translation) != "", do: Map.put(attrs, "translated_text", translation), else: attrs
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

  defp strip_html(nil), do: ""

  defp strip_html(text) do
    String.replace(text, ~r/<[^>]+>/, "")
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(text) do
    if String.contains?(text, [",", "\"", "\n"]) do
      "\"" <> String.replace(text, "\"", "\"\"") <> "\""
    else
      text
    end
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
