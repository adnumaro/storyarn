defmodule Storyarn.Localization.LocaleCodeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.SourceContract

  test "locale validation is anchored to the whole input" do
    assert LocaleCode.valid?("en")
    assert LocaleCode.valid?("pt-BR")
    refute LocaleCode.valid?("en\n")
    refute LocaleCode.valid?("pt-BR\nignored")
  end

  test "unsafe locale filenames are rejected centrally" do
    assert LocaleCode.ensure_safe!("es-419") == "es-419"
    assert LocaleCode.ensure_safe!("PT-BR") == "pt-br"

    assert_raise ArgumentError, fn ->
      LocaleCode.ensure_safe!("../../secrets")
    end
  end

  test "case variants normalize to one storage and filename representation" do
    assert LocaleCode.normalize("en-US") == "en-us"
    assert LocaleCode.normalize("EN-us") == "en-us"
  end

  test "unknown serializers fail closed for localization content roles" do
    assert SourceContract.export_content_roles(:unknown_engine) == []
    refute SourceContract.exported_content_role?(:unknown_engine, "dialogue")
  end
end
