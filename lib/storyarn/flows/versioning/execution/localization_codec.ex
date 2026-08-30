defmodule Storyarn.Flows.Versioning.LocalizationCodec do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Versioning.Adapters.Localization.VersionRestore, as: LocalizationVersionRestore
  alias Storyarn.Flows.Versioning.LocaleCode
  alias Storyarn.Flows.Versioning.Projections.LocalizedTextRecord
  alias Storyarn.Flows.Versioning.Projections.ProjectLanguageRecord
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Repo

  @manifest_fields ~w(count sha256 target_locales)
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @snapshot_fields ~w(
    source_type source_id source_field source_text source_text_hash translated_source_hash
    locale_code translated_text status vo_status vo_asset_id translator_notes reviewer_notes
    speaker_sheet_id word_count machine_translated last_translated_at last_reviewed_at
    translated_by_id reviewed_by_id archived_at archive_reason
  )

  @spec manifest([map()], [String.t()] | nil) :: map()
  def manifest(rows, target_locales \\ nil) when is_list(rows) do
    target_locales =
      target_locales
      |> Kernel.||(infer_target_locales(rows))
      |> Enum.map(&LocaleCode.normalize/1)
      |> Enum.uniq()
      |> Enum.sort()

    canonical_rows =
      rows
      |> Enum.map(&canonical_json_value/1)
      |> Enum.sort_by(&Jason.encode!/1)

    digest =
      %{"rows" => canonical_rows, "target_locales" => target_locales}
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{"count" => length(rows), "sha256" => digest, "target_locales" => target_locales}
  end

  @spec validate_manifest([map()], term()) :: :ok | {:error, term()}
  def validate_manifest(rows, manifest) when is_list(rows) and is_map(manifest) do
    with :ok <- validate_manifest_shape(manifest) do
      expected = manifest(rows, manifest["target_locales"])

      if manifest == expected,
        do: :ok,
        else: {:error, {:localization_manifest_mismatch, manifest, expected}}
    end
  end

  def validate_manifest(_rows, manifest), do: {:error, {:invalid_localization_manifest, manifest}}

  @spec active_target_locales(pos_integer()) :: [String.t()]
  def active_target_locales(project_id) do
    Repo.all(
      from(language in ProjectLanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code,
        order_by: [asc: language.locale_code]
      )
    )
  end

  @spec active_target_rows(pos_integer(), [map()]) :: [map()]
  def active_target_rows(project_id, rows) when is_list(rows) do
    active_locales = project_id |> active_target_locales() |> MapSet.new()
    Enum.filter(rows, &MapSet.member?(active_locales, &1["locale_code"]))
  end

  @spec complete_pending_rows([map()], [map()], Enumerable.t()) :: [map()]
  def complete_pending_rows(rows, sources, target_locales) when is_list(rows) and is_list(sources) do
    actual = MapSet.new(rows, &snapshot_key/1)

    missing =
      sources
      |> Enum.sort_by(&snapshot_source_key/1)
      |> Enum.flat_map(fn source ->
        target_locales
        |> Enum.sort()
        |> Enum.reject(&MapSet.member?(actual, {snapshot_source_key(source), &1}))
        |> Enum.map(&pending_snapshot_row(source, &1))
      end)

    rows ++ missing
  end

  @spec capture(pos_integer(), %{optional(String.t()) => [integer()]}, keyword()) :: [map()]
  def capture(project_id, sources, opts \\ []) do
    include_archived? = Keyword.get(opts, :include_archived, false)
    target_locales = Keyword.get_lazy(opts, :target_locales, fn -> active_target_locales(project_id) end)

    sources
    |> Enum.flat_map(fn {source_type, source_ids} ->
      query =
        from(text in LocalizedTextRecord,
          where:
            text.project_id == ^project_id and text.source_type == ^source_type and
              text.source_id in ^source_ids and text.locale_code in ^target_locales,
          order_by: [asc: text.source_id, asc: text.source_field, asc: text.locale_code]
        )

      query = if include_archived?, do: query, else: where(query, [text], is_nil(text.archived_at))
      Repo.all(query)
    end)
    |> Enum.map(&to_snapshot/1)
  end

  @spec restore(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore(_project_id, [], _id_maps), do: :ok

  def restore(project_id, rows, id_maps) do
    if Repo.in_transaction?() do
      LocalizationVersionRestore.restore(project_id, rows, id_maps)
    else
      restore_in_transaction(project_id, rows, id_maps)
    end
  end

  defp restore_in_transaction(project_id, rows, id_maps) do
    case Repo.transaction(fn ->
           rollback_failed_restore(LocalizationVersionRestore.restore(project_id, rows, id_maps))
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp rollback_failed_restore(:ok), do: :ok
  defp rollback_failed_restore({:error, reason}), do: Repo.rollback(reason)

  defp validate_manifest_shape(manifest) do
    valid? =
      manifest |> Map.keys() |> Enum.sort() == @manifest_fields and
        is_integer(manifest["count"]) and manifest["count"] >= 0 and
        is_binary(manifest["sha256"]) and Regex.match?(@sha256_regex, manifest["sha256"]) and
        valid_target_locales?(manifest["target_locales"])

    if valid?, do: :ok, else: {:error, {:invalid_localization_manifest, manifest}}
  end

  defp valid_target_locales?(target_locales) when is_list(target_locales) do
    canonical = target_locales |> Enum.uniq() |> Enum.sort()

    target_locales == canonical and
      Enum.all?(target_locales, fn locale ->
        LocaleCode.valid?(locale) and locale == LocaleCode.normalize(locale)
      end)
  end

  defp valid_target_locales?(_target_locales), do: false

  defp infer_target_locales(rows) do
    rows |> Enum.map(& &1["locale_code"]) |> Enum.filter(&is_binary/1)
  end

  defp snapshot_key(row), do: {{row["source_type"], row["source_id"], row["source_field"]}, row["locale_code"]}

  defp snapshot_source_key(source), do: {source["source_type"], source["source_id"], source["source_field"]}

  defp pending_snapshot_row(source, locale_code) do
    source_text = source["source_text"]

    %{
      "source_type" => source["source_type"],
      "source_id" => source["source_id"],
      "source_field" => source["source_field"],
      "source_text" => source_text,
      "source_text_hash" => source_text_hash(source_text),
      "translated_source_hash" => nil,
      "locale_code" => locale_code,
      "translated_text" => nil,
      "status" => "pending",
      "vo_status" => "none",
      "vo_asset_id" => nil,
      "translator_notes" => nil,
      "reviewer_notes" => nil,
      "speaker_sheet_id" => source["speaker_sheet_id"],
      "word_count" => HtmlUtils.word_count(source_text),
      "machine_translated" => false,
      "last_translated_at" => nil,
      "last_reviewed_at" => nil,
      "translated_by_id" => nil,
      "reviewed_by_id" => nil,
      "archived_at" => nil,
      "archive_reason" => nil
    }
  end

  defp source_text_hash(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end

  defp canonical_json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp canonical_json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp canonical_json_value(%Date{} = value), do: Date.to_iso8601(value)
  defp canonical_json_value(%Time{} = value), do: Time.to_iso8601(value)
  defp canonical_json_value(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp canonical_json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      [canonical_json_key(key), canonical_json_value(nested_value)]
    end)
    |> Enum.sort_by(&hd/1)
  end

  defp canonical_json_value(value) when is_list(value), do: Enum.map(value, &canonical_json_value/1)

  defp canonical_json_value(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
    do: value

  defp canonical_json_value(value), do: inspect(value)

  defp canonical_json_key(key) when is_binary(key), do: key
  defp canonical_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp canonical_json_key(key), do: to_string(key)

  defp to_snapshot(text) do
    Map.new(@snapshot_fields, fn field ->
      value = Map.fetch!(text, String.to_existing_atom(field))
      {field, canonical_snapshot_value(value)}
    end)
  end

  defp canonical_snapshot_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp canonical_snapshot_value(value), do: value
end
