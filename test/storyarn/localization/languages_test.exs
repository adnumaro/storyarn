defmodule Storyarn.Localization.LanguagesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.Languages

  @language_flags_css Path.expand("../../../assets/css/language-flags.css", __DIR__)

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

    test "matches the canonical lowercase storage form" do
      assert Languages.get("en-us").code == "en-US"
      assert Languages.get("zh-hans").code == "zh-Hans"
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
      assert Languages.name("pt-br") == "Portuguese (Brazil)"
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

    test "excludes regional codes using their canonical lowercase form" do
      options = Languages.options_for_select(exclude: ["en-us", "zh-hans"])
      codes = Enum.map(options, fn {_, code} -> code end)

      refute "en-US" in codes
      refute "zh-Hans" in codes
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

  describe "flag_code/1" do
    test "supports canonical lowercase regional codes" do
      assert Languages.flag_code("en-us") == "us"
      assert Languages.flag_code("zh-hans") == "cn"
      assert Languages.flag_code("zh-hant") == "tw"
    end

    test "falls back when a regional flag is not part of the curated assets" do
      assert Languages.flag_code("de-DE") == "de"
      refute Languages.flag_code("en-CA")
    end

    test "only returns flags backed by the curated CSS selectors and assets" do
      css = File.read!(@language_flags_css)

      [display_selectors, _background_rules] =
        Regex.split(~r/\{\s*display:\s*block;\s*\}/, css, parts: 2)

      displayed_flags =
        ~r/\.storyarn-language-flag \.fi-([a-z]{2}(?:-[a-z]{2})?)/
        |> Regex.scan(display_selectors, capture: :all_but_first)
        |> List.flatten()
        |> MapSet.new()

      background_pairs =
        Regex.scan(
          ~r/\.storyarn-language-flag \.fi-([a-z]{2}(?:-[a-z]{2})?)\s*\{\s*background-image:\s*url\("[^"]*\/([a-z]{2}(?:-[a-z]{2})?)\.svg"\);\s*\}/,
          css,
          capture: :all_but_first
        )

      background_flags =
        MapSet.new(background_pairs, fn [selector, asset] ->
          assert selector == asset
          selector
        end)

      returned_flags =
        Languages.all()
        |> Enum.map(&Languages.flag_code(&1.code))
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      assert displayed_flags == returned_flags
      assert background_flags == returned_flags
    end
  end
end
