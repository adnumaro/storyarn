defmodule StoryarnWeb.LanguagePickerOptionTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.LanguagePickerOption

  test "serializes language presentation without importing a domain catalog" do
    assert %{
             value: "pt-br",
             label: "Portuguese (Brazil)",
             languageTag: "pt-BR",
             flagCode: "br",
             shortLabel: "PT"
           } = LanguagePickerOption.from_code("pt-BR", label: "Portuguese (Brazil)")

    assert %{languageTag: "zh-Hans", flagCode: "cn", shortLabel: "ZH"} =
             LanguagePickerOption.from_code("zh-Hans", label: "Chinese (Simplified)")

    assert %{flagCode: nil, shortLabel: "LA"} =
             LanguagePickerOption.from_code("es-419", label: "Spanish (Latin America)")
  end
end
