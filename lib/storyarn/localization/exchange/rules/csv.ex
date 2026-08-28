defmodule Storyarn.Localization.Exchange.Rules.Csv do
  @moduledoc "Pure CSV and spreadsheet-safety rules for Localization exchange."

  @header "ID,Source Type,Source ID,Source Field,Locale,Source Hash,Source Text,Translation,Status,Word Count,Machine Translated"

  @spec encode([map()]) :: {:ok, String.t()}
  def encode(texts) do
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
            text.source_text |> strip_html() |> spreadsheet_safe() |> escape(),
            text.translated_text |> strip_html() |> spreadsheet_safe() |> escape(),
            text.status,
            text.word_count || 0,
            if(text.machine_translated, do: "Yes", else: "No")
          ],
          ","
        )
      end)

    {:ok, Enum.join([@header | rows], "\n")}
  end

  @spec records(String.t()) :: [String.t()]
  def records(content) do
    {records, current} = split_records(content, [], [], false)

    [record(current) | records]
    |> Enum.reverse()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec fields(String.t()) :: [String.t()]
  def fields(line) do
    line
    |> String.trim()
    |> parse([], "")
    |> Enum.reverse()
  end

  @spec column_index([String.t()], String.t()) :: non_neg_integer() | nil
  def column_index(headers, name) do
    Enum.find_index(headers, &(String.downcase(String.trim(&1)) == String.downcase(name)))
  end

  @spec spreadsheet_safe(String.t() | nil) :: String.t()
  def spreadsheet_safe(nil), do: ""

  def spreadsheet_safe(text) do
    if String.starts_with?(text, ["=", "+", "-", "@"]) do
      "'" <> text
    else
      text
    end
  end

  @spec remove_spreadsheet_escape(String.t() | nil) :: String.t() | nil
  def remove_spreadsheet_escape("'" <> rest = value) do
    if String.starts_with?(rest, ["=", "+", "-", "@"]) do
      rest
    else
      value
    end
  end

  def remove_spreadsheet_escape(value), do: value

  @spec strip_html(String.t() | nil) :: String.t()
  def strip_html(text), do: Storyarn.Platform.Shared.HtmlUtils.strip_html(text)

  defp escape(nil), do: ""

  defp escape(text) do
    if String.contains?(text, [",", "\"", "\n"]) do
      "\"" <> String.replace(text, "\"", "\"\"") <> "\""
    else
      text
    end
  end

  defp split_records("", records, current, _quoted?), do: {records, current}

  defp split_records("\"" <> rest, records, current, quoted?) do
    split_records(rest, records, ["\"" | current], not quoted?)
  end

  defp split_records("\n" <> rest, records, current, false) do
    split_records(rest, [record(current) | records], [], false)
  end

  defp split_records(<<char::utf8, rest::binary>>, records, current, quoted?) do
    split_records(rest, records, [<<char::utf8>> | current], quoted?)
  end

  defp record(current) do
    current
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\r")
  end

  defp parse("", acc, current), do: [current | acc]
  defp parse("," <> rest, acc, current), do: parse(rest, [current | acc], "")

  defp parse("\"" <> rest, acc, "") do
    {field, remaining} = parse_quoted_field(rest, "")
    parse(remaining, acc, field)
  end

  defp parse(<<char::utf8, rest::binary>>, acc, current) do
    parse(rest, acc, current <> <<char::utf8>>)
  end

  defp parse_quoted_field("\"\"" <> rest, acc), do: parse_quoted_field(rest, acc <> "\"")
  defp parse_quoted_field("\"" <> rest, acc), do: {acc, rest}

  defp parse_quoted_field(<<char::utf8, rest::binary>>, acc) do
    parse_quoted_field(rest, acc <> <<char::utf8>>)
  end

  defp parse_quoted_field("", acc), do: {acc, ""}
end
