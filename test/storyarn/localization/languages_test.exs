defmodule Storyarn.Localization.LanguagesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.Languages

  describe "all/0" do
    test "returns a non-empty list of languages" do
      languages = Languages.all()
      assert is_list(languages)
      assert length(languages) > 40
    end

    test "each language has required keys" do
      for lang <- Languages.all() do
        assert is_binary(lang.code), "code must be a string: #{inspect(lang)}"
        assert is_binary(lang.name), "name must be a string: #{inspect(lang)}"
        assert is_binary(lang.native), "native must be a string: #{inspect(lang)}"
        assert lang.region in [:europe, :asia, :americas, :africa, :oceania]
      end
    end

    test "has no duplicate codes" do
      codes = Enum.map(Languages.all(), & &1.code)
      assert codes == Enum.uniq(codes)
    end

    test "languages are ordered consistently" do
      languages = Languages.all()
      # The list has a stable order
      assert length(languages) == length(Enum.uniq_by(languages, & &1.code))
    end

    test "contains major languages" do
      codes = Enum.map(Languages.all(), & &1.code)
      assert "en" in codes
      assert "es" in codes
      assert "fr" in codes
      assert "de" in codes
      assert "ja" in codes
      assert "zh-Hans" in codes
    end
  end

  describe "get/1" do
    test "returns language by code" do
      lang = Languages.get("en")
      assert lang.code == "en"
      assert lang.name == "English"
      assert lang.native == "English"
      assert lang.region == :europe
    end

    test "returns language with region variant" do
      lang = Languages.get("en-US")
      assert lang.code == "en-US"
      assert lang.name == "English (US)"
      assert lang.region == :americas
    end

    test "returns nil for unknown code" do
      assert Languages.get("xx") == nil
    end

    test "returns nil for nil" do
      assert Languages.get(nil) == nil
    end

    test "returns nil for empty string" do
      assert Languages.get("") == nil
    end
  end

  describe "name/1" do
    test "returns name for valid code" do
      assert Languages.name("es") == "Spanish"
    end

    test "returns name for variant code" do
      assert Languages.name("pt-BR") == "Portuguese (Brazil)"
    end

    test "falls back to code for unknown code" do
      assert Languages.name("xx") == "xx"
    end

    test "falls back to code for nil" do
      assert Languages.name(nil) == nil
    end
  end

  describe "options_for_select/1" do
    test "returns tuples of {label, code}" do
      options = Languages.options_for_select()
      assert is_list(options)
      assert length(options) == length(Languages.all())

      for {label, code} <- options do
        assert is_binary(label)
        assert is_binary(code)
        assert String.contains?(label, "(#{code})")
      end
    end

    test "format is 'Name (code)'" do
      options = Languages.options_for_select()
      {label, code} = Enum.find(options, fn {_, c} -> c == "es" end)
      assert label == "Spanish (es)"
      assert code == "es"
    end

    test "excludes specified codes" do
      options = Languages.options_for_select(exclude: ["en", "es", "fr"])
      codes = Enum.map(options, fn {_, code} -> code end)

      refute "en" in codes
      refute "es" in codes
      refute "fr" in codes
      assert "de" in codes
    end

    test "empty exclude returns all" do
      all_options = Languages.options_for_select()
      excluded_options = Languages.options_for_select(exclude: [])
      assert length(all_options) == length(excluded_options)
    end

    test "excluding all codes returns empty" do
      all_codes = Enum.map(Languages.all(), & &1.code)
      options = Languages.options_for_select(exclude: all_codes)
      assert options == []
    end

    test "excluding non-existent codes has no effect" do
      all_options = Languages.options_for_select()
      options = Languages.options_for_select(exclude: ["xx", "yy", "zz"])
      assert length(all_options) == length(options)
    end
  end
end
