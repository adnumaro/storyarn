defmodule Storyarn.Workspaces.Lifecycle.Data.SourceLocaleCatalogTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workspaces

  test "the public facade exposes the complete, stable source-locale catalog" do
    locales = Workspaces.source_locale_options()
    codes = Enum.map(locales, & &1.code)

    assert length(locales) == 44
    assert codes == Enum.sort(codes)
    assert length(Enum.uniq(codes)) == length(codes)

    assert hd(locales) == %{code: "ar", name: "Arabic"}
    assert %{code: "pt-BR", name: "Portuguese (Brazil)"} in locales
    assert List.last(locales) == %{code: "zh-Hant", name: "Chinese (Traditional)"}
  end
end
