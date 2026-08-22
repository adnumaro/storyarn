defmodule StoryarnWeb.LanguagePickerOption do
  @moduledoc """
  Serializes language choices for the shared language picker.

  Picker values use the lowercase representation stored by the localization
  contexts, while `languageTag` preserves the catalog's BCP 47 casing for
  presentation and HTML metadata.
  """

  @canonical_tags %{
    "en-gb" => "en-GB",
    "en-us" => "en-US",
    "es-419" => "es-419",
    "pt-br" => "pt-BR",
    "pt-pt" => "pt-PT",
    "zh-hans" => "zh-Hans",
    "zh-hant" => "zh-Hant"
  }

  @flag_overrides %{
    "ar" => "sa",
    "bg" => "bg",
    "ca" => "es-ct",
    "cs" => "cz",
    "da" => "dk",
    "de" => "de",
    "el" => "gr",
    "en" => "gb",
    "es" => "es",
    "et" => "ee",
    "fi" => "fi",
    "fil" => "ph",
    "fr" => "fr",
    "he" => "il",
    "hi" => "in",
    "hr" => "hr",
    "hu" => "hu",
    "id" => "id",
    "it" => "it",
    "ja" => "jp",
    "ko" => "kr",
    "lt" => "lt",
    "lv" => "lv",
    "ms" => "my",
    "nb" => "no",
    "nl" => "nl",
    "pl" => "pl",
    "ro" => "ro",
    "ru" => "ru",
    "sk" => "sk",
    "sl" => "si",
    "sr" => "rs",
    "sv" => "se",
    "th" => "th",
    "tr" => "tr",
    "uk" => "ua",
    "vi" => "vn",
    "zh-hans" => "cn",
    "zh-hant" => "tw"
  }

  @supported_flag_codes @flag_overrides
                        |> Map.values()
                        |> Kernel.++(~w(gb us br pt))
                        |> MapSet.new()

  @type t :: %{
          value: String.t(),
          label: String.t(),
          languageTag: String.t(),
          flagCode: String.t() | nil,
          shortLabel: String.t()
        }

  @doc "Serializes one locale code using the shared picker contract."
  @spec from_code(String.t(), keyword()) :: t()
  def from_code(code, opts \\ []) when is_binary(code) do
    language_tag = canonical_language_tag(code)

    %{
      value: String.downcase(code),
      label: Keyword.get(opts, :label, code),
      languageTag: language_tag,
      flagCode: flag_code(language_tag),
      shortLabel: short_label(language_tag)
    }
  end

  defp canonical_language_tag(code) do
    normalized = String.replace(code, "_", "-")
    Map.get(@canonical_tags, String.downcase(normalized), normalized)
  end

  defp flag_code(code) do
    normalized = String.downcase(code)
    candidate = region_flag_code(normalized) || Map.get(@flag_overrides, normalized)

    if MapSet.member?(@supported_flag_codes, candidate), do: candidate
  end

  defp short_label(code) do
    if String.downcase(code) == "es-419" do
      "LA"
    else
      code |> String.split("-", parts: 2) |> hd() |> String.slice(0, 2) |> String.upcase()
    end
  end

  defp region_flag_code(code) do
    case String.split(code, "-", parts: 2) do
      [_language, region] when byte_size(region) == 2 -> region
      _parts -> nil
    end
  end
end
