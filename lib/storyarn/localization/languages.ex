defmodule Storyarn.Localization.Languages do
  @moduledoc """
  Static list of common languages for the language picker.

  Covers all DeepL-supported target languages plus major game localization markets.
  No external dependencies — just a curated list of ~50 languages.
  """

  @type language :: %{
          code: String.t(),
          name: String.t(),
          native: String.t(),
          region: :europe | :asia | :americas | :africa | :oceania
        }

  @languages [
    %{code: "ar", name: "Arabic", native: "العربية", region: :africa},
    %{code: "bg", name: "Bulgarian", native: "Български", region: :europe},
    %{code: "ca", name: "Catalan", native: "Català", region: :europe},
    %{code: "cs", name: "Czech", native: "Čeština", region: :europe},
    %{code: "da", name: "Danish", native: "Dansk", region: :europe},
    %{code: "de", name: "German", native: "Deutsch", region: :europe},
    %{code: "el", name: "Greek", native: "Ελληνικά", region: :europe},
    %{code: "en", name: "English", native: "English", region: :europe},
    %{code: "en-GB", name: "English (UK)", native: "English (UK)", region: :europe},
    %{code: "en-US", name: "English (US)", native: "English (US)", region: :americas},
    %{code: "es", name: "Spanish", native: "Español", region: :europe},
    %{
      code: "es-419",
      name: "Spanish (Latin America)",
      native: "Español (Latinoamérica)",
      region: :americas
    },
    %{code: "et", name: "Estonian", native: "Eesti", region: :europe},
    %{code: "fi", name: "Finnish", native: "Suomi", region: :europe},
    %{code: "fil", name: "Filipino", native: "Filipino", region: :asia},
    %{code: "fr", name: "French", native: "Français", region: :europe},
    %{code: "he", name: "Hebrew", native: "עברית", region: :asia},
    %{code: "hi", name: "Hindi", native: "हिन्दी", region: :asia},
    %{code: "hr", name: "Croatian", native: "Hrvatski", region: :europe},
    %{code: "hu", name: "Hungarian", native: "Magyar", region: :europe},
    %{code: "id", name: "Indonesian", native: "Bahasa Indonesia", region: :asia},
    %{code: "it", name: "Italian", native: "Italiano", region: :europe},
    %{code: "ja", name: "Japanese", native: "日本語", region: :asia},
    %{code: "ko", name: "Korean", native: "한국어", region: :asia},
    %{code: "lt", name: "Lithuanian", native: "Lietuvių", region: :europe},
    %{code: "lv", name: "Latvian", native: "Latviešu", region: :europe},
    %{code: "ms", name: "Malay", native: "Bahasa Melayu", region: :asia},
    %{code: "nb", name: "Norwegian Bokmål", native: "Norsk bokmål", region: :europe},
    %{code: "nl", name: "Dutch", native: "Nederlands", region: :europe},
    %{code: "pl", name: "Polish", native: "Polski", region: :europe},
    %{
      code: "pt-BR",
      name: "Portuguese (Brazil)",
      native: "Português (Brasil)",
      region: :americas
    },
    %{
      code: "pt-PT",
      name: "Portuguese (Portugal)",
      native: "Português (Portugal)",
      region: :europe
    },
    %{code: "ro", name: "Romanian", native: "Română", region: :europe},
    %{code: "ru", name: "Russian", native: "Русский", region: :europe},
    %{code: "sk", name: "Slovak", native: "Slovenčina", region: :europe},
    %{code: "sl", name: "Slovenian", native: "Slovenščina", region: :europe},
    %{code: "sr", name: "Serbian", native: "Српски", region: :europe},
    %{code: "sv", name: "Swedish", native: "Svenska", region: :europe},
    %{code: "th", name: "Thai", native: "ไทย", region: :asia},
    %{code: "tr", name: "Turkish", native: "Türkçe", region: :europe},
    %{code: "uk", name: "Ukrainian", native: "Українська", region: :europe},
    %{code: "vi", name: "Vietnamese", native: "Tiếng Việt", region: :asia},
    %{code: "zh-Hans", name: "Chinese (Simplified)", native: "简体中文", region: :asia},
    %{code: "zh-Hant", name: "Chinese (Traditional)", native: "繁體中文", region: :asia}
  ]

  @languages_by_code Map.new(@languages, &{&1.code, &1})

  @flag_overrides %{
    "ar" => "sa",
    "bg" => "bg",
    "ca" => "ad",
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
    "zh-Hans" => "cn",
    "zh-Hant" => "tw"
  }

  @short_label_overrides %{
    "es-419" => "LA"
  }

  @doc "Returns all languages sorted by name."
  @spec all() :: [language()]
  def all, do: @languages

  @doc "Returns a single language map by code, or nil."
  @spec get(String.t()) :: language() | nil
  def get(code), do: Map.get(@languages_by_code, code)

  @doc "Returns the display name for a code, falling back to the code itself."
  @spec name(String.t()) :: String.t()
  def name(code) do
    case Map.get(@languages_by_code, code) do
      %{name: name} -> name
      nil -> code
    end
  end

  @doc "Returns the ISO alpha-2 country code used for a locale flag, or nil when there is no good flag."
  @spec flag_code(String.t()) :: String.t() | nil
  def flag_code(code) do
    region_flag_code(code) || Map.get(@flag_overrides, code)
  end

  @doc "Returns a compact fallback label for a locale when there is no flag."
  @spec short_label(String.t()) :: String.t()
  def short_label(code) do
    Map.get(@short_label_overrides, code) ||
      code
      |> String.split("-", parts: 2)
      |> hd()
      |> String.slice(0, 2)
      |> String.upcase()
  end

  @doc """
  Returns `[{display_label, code}]` tuples for use in `<select>` options.

  Display format: `"Spanish (es)"`.

  ## Options

    * `:exclude` - list of codes to exclude (e.g., already-added languages)

  """
  @spec options_for_select(keyword()) :: [{String.t(), String.t()}]
  def options_for_select(opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [])
    exclude_set = MapSet.new(exclude)

    @languages
    |> Enum.reject(&MapSet.member?(exclude_set, &1.code))
    |> Enum.map(&{"#{&1.name} (#{&1.code})", &1.code})
  end

  defp region_flag_code(code) do
    case String.split(code, "-", parts: 2) do
      [_language, region] when byte_size(region) == 2 -> String.downcase(region)
      _ -> nil
    end
  end
end
