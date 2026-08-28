defmodule Storyarn.Projects.LocalizationLanguageCatalog do
  @moduledoc false

  @languages [
    %{code: "ar", name: "Arabic"},
    %{code: "bg", name: "Bulgarian"},
    %{code: "ca", name: "Catalan"},
    %{code: "cs", name: "Czech"},
    %{code: "da", name: "Danish"},
    %{code: "de", name: "German"},
    %{code: "el", name: "Greek"},
    %{code: "en", name: "English"},
    %{code: "en-GB", name: "English (UK)"},
    %{code: "en-US", name: "English (US)"},
    %{code: "es", name: "Spanish"},
    %{code: "es-419", name: "Spanish (Latin America)"},
    %{code: "et", name: "Estonian"},
    %{code: "fi", name: "Finnish"},
    %{code: "fil", name: "Filipino"},
    %{code: "fr", name: "French"},
    %{code: "he", name: "Hebrew"},
    %{code: "hi", name: "Hindi"},
    %{code: "hr", name: "Croatian"},
    %{code: "hu", name: "Hungarian"},
    %{code: "id", name: "Indonesian"},
    %{code: "it", name: "Italian"},
    %{code: "ja", name: "Japanese"},
    %{code: "ko", name: "Korean"},
    %{code: "lt", name: "Lithuanian"},
    %{code: "lv", name: "Latvian"},
    %{code: "ms", name: "Malay"},
    %{code: "nb", name: "Norwegian Bokmål"},
    %{code: "nl", name: "Dutch"},
    %{code: "pl", name: "Polish"},
    %{code: "pt-BR", name: "Portuguese (Brazil)"},
    %{code: "pt-PT", name: "Portuguese (Portugal)"},
    %{code: "ro", name: "Romanian"},
    %{code: "ru", name: "Russian"},
    %{code: "sk", name: "Slovak"},
    %{code: "sl", name: "Slovenian"},
    %{code: "sr", name: "Serbian"},
    %{code: "sv", name: "Swedish"},
    %{code: "th", name: "Thai"},
    %{code: "tr", name: "Turkish"},
    %{code: "uk", name: "Ukrainian"},
    %{code: "vi", name: "Vietnamese"},
    %{code: "zh-Hans", name: "Chinese (Simplified)"},
    %{code: "zh-Hant", name: "Chinese (Traditional)"}
  ]

  @by_code Map.new(@languages, &{String.downcase(&1.code), &1})
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
                        |> Kernel.++(
                          @languages
                          |> Enum.map(fn %{code: code} ->
                            case String.split(String.downcase(code), "-", parts: 2) do
                              [_language, region] when byte_size(region) == 2 -> region
                              _ -> nil
                            end
                          end)
                          |> Enum.reject(&is_nil/1)
                        )
                        |> MapSet.new()

  def name(code) when is_binary(code) do
    case Map.get(@by_code, String.downcase(code)) do
      %{name: name} -> name
      nil -> code
    end
  end

  def options, do: Enum.map(@languages, &option(&1.code, &1.name))

  def option(code, label \\ nil) when is_binary(code) do
    language_tag = canonical_tag(code)

    %{
      value: String.downcase(code),
      label: label || name(code),
      languageTag: language_tag,
      flagCode: flag_code(language_tag),
      shortLabel: short_label(language_tag)
    }
  end

  defp canonical_tag(code) do
    case Map.get(@by_code, String.downcase(code)) do
      %{code: canonical} -> canonical
      nil -> String.replace(code, "_", "-")
    end
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
      [_language, region] when byte_size(region) == 2 -> String.downcase(region)
      _ -> nil
    end
  end
end
