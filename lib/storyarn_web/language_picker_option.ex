defmodule StoryarnWeb.LanguagePickerOption do
  @moduledoc """
  Serializes language choices for the shared language picker.

  Picker values use the lowercase representation stored by the localization
  contexts, while `languageTag` preserves the catalog's BCP 47 casing for
  presentation and HTML metadata.
  """

  alias Storyarn.Localization.Languages

  @type t :: %{
          value: String.t(),
          label: String.t(),
          languageTag: String.t(),
          flagCode: String.t() | nil,
          shortLabel: String.t()
        }

  @doc "Returns every catalog language using the shared picker contract."
  @spec all() :: [t()]
  def all do
    Enum.map(Languages.all(), fn language ->
      from_code(language.code, label: language.name)
    end)
  end

  @doc "Serializes one locale code using the shared picker contract."
  @spec from_code(String.t(), keyword()) :: t()
  def from_code(code, opts \\ []) when is_binary(code) do
    language_tag = canonical_language_tag(code)

    %{
      value: String.downcase(code),
      label: Keyword.get(opts, :label, Languages.name(code)),
      languageTag: language_tag,
      flagCode: Languages.flag_code(language_tag),
      shortLabel: Languages.short_label(language_tag)
    }
  end

  defp canonical_language_tag(code) do
    case Languages.get(code) do
      %{code: language_tag} -> language_tag
      nil -> String.replace(code, "_", "-")
    end
  end
end
