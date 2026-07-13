defmodule Storyarn.Exports.LocalizationCatalog do
  @moduledoc false

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.Serializers.Helpers
  alias Storyarn.Localization.ExportPolicy
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Shared.MapUtils

  @doc "Returns the stable key shared by engine content and external catalogs."
  @spec key(term(), term(), term()) :: String.t()
  defdelegate key(source_type, source_ref, source_field), to: RuntimeKey

  @spec key(map()) :: String.t()
  def key(text) do
    case attr(text, :localization_key) do
      value when is_binary(value) and value != "" -> value
      value -> raise ArgumentError, "missing runtime localization key: #{inspect(value)}"
    end
  end

  defdelegate for_flow_node(node, source_field), to: RuntimeKey
  defdelegate for_block(block, sheet_shortcut, source_field), to: RuntimeKey
  defdelegate for_sheet(sheet, source_field), to: RuntimeKey

  @doc "Returns whether a localization row can be addressed by the selected serializer."
  def text_supported?(text, %ExportOptions{format: format}) do
    case content_role(text) do
      nil -> false
      role -> SourceContract.exported_content_role?(format, role)
    end
  end

  @spec files(map() | nil, ExportOptions.t(), :generic | :godot | :unreal) ::
          [{String.t(), binary()}]
  def files(_localization, %ExportOptions{include_localization: false}, _format), do: []
  def files(nil, _opts, _format), do: []

  def files(localization, opts, :godot) do
    rows = eligible_rows(localization, opts)
    locales = rows |> Enum.map(& &1.locale) |> Enum.uniq() |> Enum.sort()

    catalog_files =
      if locales == [] do
        []
      else
        translations = Map.new(rows, &{{&1.key, &1.locale}, &1.text})

        matrix_rows =
          rows
          |> Enum.map(& &1.key)
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.map(fn key -> [key | Enum.map(locales, &Map.get(translations, {key, &1}, ""))] end)

        [{"translations.csv", Helpers.build_csv(["keys" | locales], matrix_rows)}]
      end

    catalog_files ++ manifest_files(localization, opts)
  end

  def files(localization, opts, :unreal) do
    catalog_files =
      localization
      |> eligible_rows(opts)
      |> Enum.group_by(& &1.locale)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {locale, rows} ->
        content = Helpers.build_csv(["Key", "SourceString"], Enum.map(rows, &[&1.key, &1.text]))
        {"StringTable.#{locale}.csv", content}
      end)

    catalog_files ++ manifest_files(localization, opts)
  end

  def files(localization, opts, :generic) do
    catalog_files =
      localization
      |> eligible_rows(opts)
      |> Enum.group_by(& &1.locale)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {locale, rows} ->
        csv_rows = Enum.map(rows, &[&1.key, &1.text, &1.source_type, &1.source_id, &1.source_field])

        {"localization.#{locale}.csv",
         Helpers.build_csv(["Key", "Text", "SourceType", "SourceId", "SourceField"], csv_rows)}
      end)

    catalog_files ++ manifest_files(localization, opts)
  end

  @doc "Builds the machine-readable localization policy manifest sidecar."
  def manifest_files(_localization, %ExportOptions{include_localization: false}), do: []
  def manifest_files(nil, _opts), do: []

  def manifest_files(localization, opts) do
    strings = target_strings(localization, opts)

    if strings == [] do
      []
    else
      manifest = build_manifest(strings, opts)
      [{"localization-manifest.json", Jason.encode!(manifest, pretty: true)}]
    end
  end

  @doc "Builds localization policy metadata for embedded serializers."
  def manifest(_localization, %ExportOptions{include_localization: false}), do: nil
  def manifest(nil, _opts), do: nil

  def manifest(localization, opts) do
    case target_strings(localization, opts) do
      [] -> nil
      strings -> build_manifest(strings, opts)
    end
  end

  defp build_manifest(strings, opts) do
    exported = Enum.count(strings, &ExportPolicy.text_eligible?(&1, opts))
    release_ready = Enum.count(strings, &ExportPolicy.text_eligible?(&1, :release))
    preview_ready = Enum.count(strings, &ExportPolicy.text_eligible?(&1, :preview))
    excluded = length(strings) - exported
    non_release = max(preview_ready - release_ready, 0)

    warnings =
      case opts.localization_policy do
        :release when excluded > 0 ->
          ["#{excluded} localization strings were excluded because they are not release-ready."]

        :preview when non_release > 0 ->
          ["Preview includes #{non_release} non-final or outdated localization strings."]

        _other ->
          []
      end

    %{
      "version" => 1,
      "policy" => Atom.to_string(opts.localization_policy),
      "totalStrings" => length(strings),
      "exportedStrings" => exported,
      "excludedStrings" => excluded,
      "releaseReadyStrings" => release_ready,
      "previewReadyStrings" => preview_ready,
      "warnings" => warnings
    }
  end

  defp eligible_rows(localization, opts) do
    localization
    |> target_strings(opts)
    |> Enum.filter(&ExportPolicy.text_eligible?(&1, opts))
    |> Enum.map(fn text ->
      source_type = attr(text, :source_type)
      source_id = attr(text, :source_id)
      source_field = attr(text, :source_field)

      %{
        key: key(text),
        locale: LocaleCode.ensure_safe!(attr(text, :locale_code)),
        text: normalize_translation(attr(text, :translated_text)),
        source_type: source_type,
        source_id: source_id,
        source_field: source_field
      }
    end)
    |> Enum.sort_by(&{&1.locale, &1.key})
  end

  defp target_strings(localization, opts) do
    languages = attr(localization, :languages) || []
    strings = attr(localization, :strings) || []

    source_locales =
      languages
      |> Enum.filter(&(attr(&1, :is_source) == true))
      |> MapSet.new(&(&1 |> attr(:locale_code) |> LocaleCode.ensure_safe!()))

    strings
    |> Enum.reject(&MapSet.member?(source_locales, &1 |> attr(:locale_code) |> LocaleCode.ensure_safe!()))
    |> Enum.filter(fn text -> is_nil(attr(text, :archived_at)) and text_supported?(text, opts) end)
  end

  defp content_role(text) do
    attr(text, :content_role) ||
      case SourceContract.field_metadata(attr(text, :source_type), attr(text, :source_field)) do
        nil -> nil
        metadata -> metadata.content_role
      end
  end

  defp normalize_translation(nil), do: ""
  defp normalize_translation(value), do: value |> to_string() |> Helpers.strip_html()

  defp attr(record, field), do: MapUtils.get_flexible(record, field)
end
