defmodule Storyarn.Localization.Exchange.Adapters.Xlsx.Encoder do
  @moduledoc "Technical adapter that encodes Localization exchange rows as XLSX."

  alias Storyarn.Localization.Exchange.Rules.Csv

  @header [
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

  @spec encode([map()]) :: {:ok, binary()}
  def encode(texts) do
    rows =
      Enum.map(texts, fn text ->
        [
          text.id,
          text.source_type,
          text.source_id,
          text.source_field,
          text.locale_code,
          text.source_text_hash,
          text.source_text |> Csv.strip_html() |> Csv.spreadsheet_safe(),
          text.translated_text |> Csv.strip_html() |> Csv.spreadsheet_safe(),
          text.status,
          text.word_count || 0,
          if(text.machine_translated, do: "Yes", else: "No"),
          text.translator_notes || "",
          text.reviewer_notes || ""
        ]
      end)

    workbook = %Elixlsx.Workbook{
      sheets: [%Elixlsx.Sheet{name: "Translations", rows: [@header | rows]}]
    }

    {:ok, {_filename, binary}} = Elixlsx.write_to_memory(workbook, "translations.xlsx")
    {:ok, binary}
  end
end
