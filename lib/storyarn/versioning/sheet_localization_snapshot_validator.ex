defmodule Storyarn.Versioning.SheetLocalizationSnapshotValidator do
  @moduledoc false

  alias Storyarn.Localization.HtmlHandler
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Shared.HtmlUtils

  @localization_snapshot_fields ~w(
    source_type source_id source_field source_text source_text_hash translated_source_hash
    locale_code translated_text status vo_status vo_asset_id translator_notes reviewer_notes
    speaker_sheet_id word_count machine_translated last_translated_at last_reviewed_at
    translated_by_id reviewed_by_id archived_at archive_reason
  )

  @spec validate([map()], map()) :: :ok | {:error, term()}
  def validate(localization, snapshot) when is_list(localization) and is_map(snapshot) do
    target_locales = get_in(snapshot, ["localization_manifest", "target_locales"])

    with :ok <- validate_snapshot_source_shape(snapshot),
         sources = snapshot_sources(snapshot),
         :ok <- validate_rows(localization, sources),
         :ok <- validate_unique_rows(localization),
         {:ok, target_locales} <- validate_locales(localization, target_locales) do
      validate_complete_inventory(localization, sources, target_locales)
    end
  end

  def validate(localization, snapshot), do: {:error, {:invalid_sheet_localization_snapshot, localization, snapshot}}

  @spec validate_sources([map()], map()) :: :ok | {:error, term()}
  def validate_sources(localization, snapshot) when is_list(localization) and is_map(snapshot) do
    with :ok <- validate_snapshot_source_shape(snapshot),
         sources = snapshot_sources(snapshot),
         :ok <- validate_rows(localization, sources) do
      validate_unique_rows(localization)
    end
  end

  def validate_sources(localization, snapshot),
    do: {:error, {:invalid_sheet_localization_snapshot, localization, snapshot}}

  defp validate_rows(localization, sources) do
    Enum.reduce_while(localization, :ok, fn row, :ok ->
      case validate_row(row, sources) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_row(%{} = row, sources) do
    source_key = {row["source_type"], row["source_id"], row["source_field"]}
    source = Map.get(sources, source_key)

    with :ok <- validate_exact_keys(row),
         true <- row["source_type"] in ~w(sheet block),
         true <- positive_integer?(row["source_id"]),
         true <- is_map(source),
         true <- SourceContract.field?(row["source_type"], row["source_field"]),
         true <-
           SourceContract.localizable_source_field?(
             row["source_type"],
             source.runtime_source,
             row["source_field"]
           ),
         true <- is_binary(row["source_text"]),
         true <- sha256?(row["source_text_hash"]),
         true <- optional_sha256?(row["translated_source_hash"]),
         true <- LocaleCode.valid?(row["locale_code"]),
         true <- row["locale_code"] == LocaleCode.normalize(row["locale_code"]),
         true <- optional_string?(row["translated_text"]),
         true <- row["status"] in ~w(pending draft in_progress review final),
         true <- row["vo_status"] in ~w(none needed recorded approved),
         true <- optional_positive_integer?(row["vo_asset_id"]),
         true <- optional_string?(row["translator_notes"]),
         true <- optional_string?(row["reviewer_notes"]),
         true <- optional_positive_integer?(row["speaker_sheet_id"]),
         true <- is_integer(row["word_count"]) and row["word_count"] >= 0,
         true <- is_boolean(row["machine_translated"]),
         true <- valid_datetime?(row["last_translated_at"]),
         true <- valid_datetime?(row["last_reviewed_at"]),
         true <- optional_positive_integer?(row["translated_by_id"]),
         true <- optional_positive_integer?(row["reviewed_by_id"]),
         true <- valid_datetime?(row["archived_at"]),
         true <- optional_string?(row["archive_reason"]) do
      validate_row_semantics(row, source)
    else
      false -> {:error, {:invalid_sheet_localization_snapshot, row}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_row(row, _sources), do: {:error, {:invalid_sheet_localization_snapshot, row}}

  defp validate_exact_keys(row) do
    expected = MapSet.new(@localization_snapshot_fields)
    actual = MapSet.new(Map.keys(row))

    if actual == expected do
      :ok
    else
      {:error,
       {:invalid_snapshot_fields, :localization,
        %{
          missing: sorted_difference(expected, actual),
          unexpected: sorted_difference(actual, expected)
        }}}
    end
  end

  defp sorted_difference(left, right) do
    left
    |> MapSet.difference(right)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp validate_row_semantics(row, source) do
    expected_hash = source_text_hash(source.text)

    with :ok <- require_equal(row, "source_text", source.text, :localization_source_text_mismatch),
         :ok <-
           require_equal(
             row,
             "source_text_hash",
             expected_hash,
             :localization_source_text_hash_mismatch
           ),
         :ok <-
           require_equal(
             row,
             "word_count",
             HtmlUtils.word_count(source.text),
             :localization_word_count_mismatch
           ),
         :ok <-
           require_equal(
             row,
             "speaker_sheet_id",
             source.speaker_sheet_id,
             :localization_speaker_mismatch
           ),
         :ok <- validate_active_state(row),
         :ok <- validate_translation_state(row),
         :ok <- validate_translation_placeholders(row) do
      validate_voiceover_state(row, source.metadata)
    end
  end

  defp require_equal(row, field, expected, error_tag) do
    if row[field] == expected do
      :ok
    else
      {:error, {error_tag, row["source_type"], row["source_id"], row["source_field"]}}
    end
  end

  defp validate_active_state(row) do
    if is_nil(row["archived_at"]) and is_nil(row["archive_reason"]) do
      :ok
    else
      {:error,
       {:invalid_active_localization_archive_state, row["source_type"], row["source_id"], row["source_field"],
        row["locale_code"]}}
    end
  end

  defp validate_translation_state(row) do
    if coherent_translation_state?(row) do
      :ok
    else
      {:error,
       {:invalid_localization_translation_state, row["source_type"], row["source_id"], row["source_field"],
        row["locale_code"]}}
    end
  end

  defp validate_translation_placeholders(%{"source_text" => source_text, "translated_text" => translated_text} = row)
       when is_binary(translated_text) do
    case HtmlHandler.validate_placeholders(source_text, translated_text) do
      :ok ->
        :ok

      {:error, details} ->
        {:error,
         {:invalid_localization_placeholders, row["source_type"], row["source_id"], row["source_field"],
          row["locale_code"], details}}
    end
  end

  defp validate_translation_placeholders(_row), do: :ok

  defp validate_voiceover_state(row, %{vo_eligible: false}) do
    if row["vo_status"] == "none" and is_nil(row["vo_asset_id"]) do
      :ok
    else
      {:error,
       {:invalid_localization_voiceover_state, row["source_type"], row["source_id"], row["source_field"],
        row["locale_code"]}}
    end
  end

  defp validate_voiceover_state(row, %{vo_eligible: true}) do
    if row["vo_status"] not in ~w(recorded approved) or positive_integer?(row["vo_asset_id"]) do
      :ok
    else
      {:error,
       {:invalid_localization_voiceover_state, row["source_type"], row["source_id"], row["source_field"],
        row["locale_code"]}}
    end
  end

  defp coherent_translation_state?(row) do
    translated? = present_string?(row["translated_text"])
    translated_hash = row["translated_source_hash"]

    coherent_translation_text?(row["translated_text"]) and
      coherent_translation_hash?(translated?, translated_hash) and
      coherent_machine_translation?(row["machine_translated"], translated?) and
      coherent_final_translation?(
        row["status"],
        translated?,
        translated_hash,
        row["source_text_hash"]
      )
  end

  defp coherent_translation_text?(nil), do: true
  defp coherent_translation_text?(text), do: present_string?(text)

  defp coherent_translation_hash?(false, nil), do: true
  defp coherent_translation_hash?(false, _translated_hash), do: false
  defp coherent_translation_hash?(true, translated_hash), do: sha256?(translated_hash)

  defp coherent_machine_translation?(false, _translated?), do: true
  defp coherent_machine_translation?(true, translated?), do: translated?

  defp coherent_final_translation?("final", true, translated_hash, source_hash), do: translated_hash == source_hash

  defp coherent_final_translation?("final", false, _translated_hash, _source_hash), do: false
  defp coherent_final_translation?(_status, _translated?, _translated_hash, _source_hash), do: true

  defp validate_unique_rows(localization) do
    keys =
      Enum.map(localization, fn row ->
        {row["source_type"], row["source_id"], row["source_field"], row["locale_code"]}
      end)

    if length(keys) == length(Enum.uniq(keys)),
      do: :ok,
      else: {:error, :duplicate_sheet_localization_snapshot}
  end

  defp validate_locales(localization, target_locales) when is_list(target_locales) do
    target_locales = MapSet.new(target_locales)

    case Enum.find(localization, &(not MapSet.member?(target_locales, &1["locale_code"]))) do
      nil ->
        {:ok, target_locales}

      row ->
        {:error,
         {:localization_locale_outside_snapshot, row["source_type"], row["source_id"], row["source_field"],
          row["locale_code"]}}
    end
  end

  defp validate_locales(_localization, target_locales),
    do: {:error, {:invalid_localization_target_locales, target_locales}}

  defp validate_complete_inventory(localization, sources, target_locales) do
    expected =
      for {source_key, _source} <- sources,
          locale <- target_locales,
          into: MapSet.new() do
        {source_key, locale}
      end

    actual =
      MapSet.new(localization, fn row ->
        {{row["source_type"], row["source_id"], row["source_field"]}, row["locale_code"]}
      end)

    if actual == expected do
      :ok
    else
      {:error,
       {:incomplete_sheet_localization_snapshot,
        %{
          missing: sorted_difference(expected, actual),
          unexpected: sorted_difference(actual, expected)
        }}}
    end
  end

  defp validate_snapshot_source_shape(snapshot) do
    with :ok <- validate_snapshot_source_name(snapshot["name"]),
         :ok <- validate_snapshot_source_id(snapshot["original_id"]) do
      validate_snapshot_source_blocks(snapshot["blocks"])
    end
  end

  defp validate_snapshot_source_name(name) when is_binary(name), do: :ok
  defp validate_snapshot_source_name(name), do: {:error, {:invalid_sheet_localization_source, :name, name}}

  defp validate_snapshot_source_id(id) do
    if positive_integer?(id),
      do: :ok,
      else: {:error, {:invalid_sheet_localization_source, :original_id, id}}
  end

  defp validate_snapshot_source_blocks(blocks) when is_list(blocks) do
    case Enum.find(blocks, &(not valid_snapshot_source_block?(&1))) do
      nil -> :ok
      malformed -> {:error, {:invalid_sheet_localization_source, :block, malformed}}
    end
  end

  defp validate_snapshot_source_blocks(blocks), do: {:error, {:invalid_sheet_localization_source, :blocks, blocks}}

  defp valid_snapshot_source_block?(block) when is_map(block) do
    positive_integer?(block["original_id"]) and
      is_binary(block["type"]) and
      is_map(block["value"]) and
      is_boolean(block["is_constant"]) and
      optional_string?(block["variable_name"])
  end

  defp valid_snapshot_source_block?(_block), do: false

  defp snapshot_sources(snapshot) do
    %{}
    |> maybe_put_source(
      "sheet",
      snapshot["original_id"],
      "name",
      snapshot["name"],
      %{deleted_at: nil}
    )
    |> add_block_sources(snapshot["blocks"])
  end

  defp add_block_sources(sources, blocks) when is_list(blocks) do
    Enum.reduce(blocks, sources, fn block, acc ->
      runtime_source = %{
        type: block["type"],
        is_constant: block["is_constant"],
        variable_name: block["variable_name"],
        deleted_at: nil
      }

      if SourceContract.localizable_block?(runtime_source) do
        maybe_put_source(
          acc,
          "block",
          block["original_id"],
          "value.content",
          get_in(block, ["value", "content"]),
          runtime_source
        )
      else
        acc
      end
    end)
  end

  defp add_block_sources(sources, _blocks), do: sources

  defp maybe_put_source(sources, source_type, source_id, source_field, text, runtime_source) when is_binary(text) do
    if HtmlUtils.strip_html(text) == "" do
      sources
    else
      Map.put(
        sources,
        {source_type, source_id, source_field},
        %{
          text: text,
          runtime_source: runtime_source,
          speaker_sheet_id: nil,
          metadata: SourceContract.field_metadata(source_type, source_field)
        }
      )
    end
  end

  defp maybe_put_source(sources, _source_type, _source_id, _source_field, _text, _runtime_source), do: sources

  defp source_text_hash(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end

  defp valid_datetime?(nil), do: true
  defp valid_datetime?(%DateTime{}), do: true

  defp valid_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_datetime?(_value), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp optional_positive_integer?(value), do: is_nil(value) or positive_integer?(value)
  defp optional_string?(value), do: is_nil(value) or is_binary(value)
  defp optional_sha256?(nil), do: true
  defp optional_sha256?(value), do: sha256?(value)
  defp sha256?(value) when is_binary(value), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp sha256?(_value), do: false
  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
end
