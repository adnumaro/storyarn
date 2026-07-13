defmodule Storyarn.Exports.LocalizationCatalogTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.LocalizationCatalog

  test "release catalogs exclude unfinished, stale, and archived strings and explain the result" do
    files = LocalizationCatalog.files(localization(), options(:release), :generic)

    assert {"localization.es.csv", csv} = List.keyfind(files, "localization.es.csv", 0)
    assert csv =~ "Final translation"
    refute csv =~ "Draft translation"
    refute csv =~ "Stale translation"
    refute csv =~ "Archived translation"

    manifest = manifest(files)
    assert manifest["policy"] == "release"
    assert manifest["totalStrings"] == 3
    assert manifest["exportedStrings"] == 1
    assert manifest["excludedStrings"] == 2
    assert manifest["warnings"] != []
  end

  test "preview catalogs include non-final and stale strings with an explicit warning" do
    files = LocalizationCatalog.files(localization(), options(:preview), :godot)

    assert {"translations.csv", csv} = List.keyfind(files, "translations.csv", 0)
    assert csv =~ "Final translation"
    assert csv =~ "Draft translation"
    assert csv =~ "Stale translation"
    refute csv =~ "Archived translation"

    manifest = manifest(files)
    assert manifest["policy"] == "preview"
    assert manifest["exportedStrings"] == 3
    assert manifest["excludedStrings"] == 0
    assert manifest["warnings"] == ["Preview includes 2 non-final or outdated localization strings."]
  end

  test "catalog translations use the same plain-text representation as engine exports" do
    localization =
      update_in(localization(), [:strings], fn [final | rest] ->
        [%{final | translated_text: "<p>Hola<br>mundo &amp; amigos</p>"} | rest]
      end)

    files = LocalizationCatalog.files(localization, options(:release), :generic)

    assert {"localization.es.csv", csv} = List.keyfind(files, "localization.es.csv", 0)
    assert csv =~ "Hola\nmundo & amigos"
    refute csv =~ "<p>"
    refute csv =~ "&amp;"
  end

  test "unsafe locale identifiers cannot become export filenames" do
    localization = %{
      languages: [
        %{locale_code: "en", is_source: true},
        %{locale_code: "../../outside", is_source: false}
      ],
      strings: [1 |> text("Translation", "final", "hash", nil) |> Map.put(:locale_code, "../../outside")]
    }

    assert_raise ArgumentError, ~r/invalid localization locale/, fn ->
      LocalizationCatalog.files(localization, options(:release), :generic)
    end
  end

  test "embedded manifest is omitted when localization is disabled" do
    opts = %ExportOptions{format: :ink, include_localization: false}
    assert LocalizationCatalog.manifest(localization(), opts) == nil
  end

  test "source locale exclusion is case-insensitive through canonical locale codes" do
    data =
      localization()
      |> put_in([:languages, Access.at(0), :locale_code], "EN")
      |> update_in([:strings], fn strings ->
        [%{hd(strings) | locale_code: "en"} | strings]
      end)

    files = LocalizationCatalog.files(data, options(:release), :generic)
    refute Enum.any?(files, fn {name, _content} -> name == "localization.en.csv" end)
  end

  defp manifest(files) do
    {"localization-manifest.json", json} = List.keyfind(files, "localization-manifest.json", 0)
    Jason.decode!(json)
  end

  defp options(policy) do
    %ExportOptions{format: :ink, localization_policy: policy}
  end

  defp localization do
    %{
      languages: [
        %{locale_code: "en", is_source: true},
        %{locale_code: "es", is_source: false}
      ],
      strings: [
        text(1, "Final translation", "final", "hash", nil),
        text(2, "Draft translation", "draft", "hash", nil),
        text(3, "Stale translation", "final", "old-hash", nil),
        text(4, "Archived translation", "final", "hash", DateTime.utc_now())
      ]
    }
  end

  defp text(id, translation, status, translated_hash, archived_at) do
    %{
      source_type: "flow_node",
      source_id: id,
      source_field: "text",
      localization_key: "flow_node.dialogue_#{id}.text",
      locale_code: "es",
      translated_text: translation,
      status: status,
      source_text_hash: "hash",
      translated_source_hash: translated_hash,
      archived_at: archived_at
    }
  end
end
