defmodule Storyarn.Publication.LocalesTest do
  use ExUnit.Case, async: true

  alias Expo.Message
  alias Expo.Message.Plural
  alias Expo.Message.Singular
  alias Storyarn.Blog
  alias Storyarn.Docs.Guide
  alias Storyarn.Publication.Locales

  @project_root Path.expand("../../..", __DIR__)
  @public_gettext_domains ~w(public docs blog)

  test "exposes the canonical default and localized public locales" do
    assert Locales.default_locale() == "en"
    assert Locales.locales() == ["en", "es"]
    assert Locales.localized_locales() == ["es"]

    assert Locales.descriptors() == [
             %{gettext_locale: "en", language_tag: "en", path_segment: "en"},
             %{gettext_locale: "es", language_tag: "es", path_segment: "es"}
           ]

    assert Locales.localized_routes() == [{"es", "es"}]
  end

  test "maps Gettext locales, language tags, and URL path segments independently" do
    assert Locales.language_tag("en") == "en"
    assert Locales.language_tag("es") == "es"
    assert Locales.language_tag("pt_BR") == "pt-BR"

    assert Locales.path_segment("en") == "en"
    assert Locales.path_segment("es") == "es"
    assert Locales.locale_from_path_segment("ES") == "es"
    assert Locales.localized_locale_from_path_segment("es") == "es"
    assert Locales.localized_locale_from_path_segment("en") == nil
    assert Locales.locale_from_path_segment("unknown") == nil
  end

  test "validates and normalizes only fully published public locales" do
    assert Locales.valid?("en")
    assert Locales.valid?("es")
    refute Locales.valid?("fr")
    refute Locales.valid?(nil)

    assert Locales.normalize("es") == "es"
    assert Locales.normalize("de") == "en"
    assert Locales.normalize(nil) == "en"
  end

  test "every published locale has a complete public content surface" do
    assert_complete_gettext_catalogs()
    assert_complete_vue_catalogs()
    assert_complete_docs()
    assert_complete_blog()
  end

  defp assert_complete_gettext_catalogs do
    Enum.each(@public_gettext_domains, fn domain ->
      template = parse_po!("priv/gettext/#{domain}.pot")
      template_keys = message_keys(template.messages)

      Enum.each(
        Locales.locales(),
        &assert_complete_gettext_catalog(&1, domain, template_keys)
      )
    end)
  end

  defp assert_complete_gettext_catalog(locale, domain, template_keys) do
    relative_path = "priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po"
    catalog = parse_po!(relative_path)

    assert message_keys(catalog.messages) == template_keys,
           "#{relative_path} must contain exactly the messages from #{domain}.pot"

    if locale != Locales.default_locale() do
      assert Enum.all?(catalog.messages, &(not Message.has_flag?(&1, "fuzzy"))),
             "#{relative_path} contains fuzzy translations"

      assert Enum.all?(catalog.messages, &translated?(&1, catalog)),
             "#{relative_path} contains missing translations"
    end
  end

  defp assert_complete_vue_catalogs do
    default_locale = Locales.default_locale()
    default_catalogs = vue_catalogs(default_locale)
    default_files = default_catalogs |> Map.keys() |> MapSet.new()

    Enum.each(Locales.locales(), fn locale ->
      catalogs = vue_catalogs(locale)

      assert MapSet.new(Map.keys(catalogs)) == default_files,
             "assets/app/locales/#{locale} must contain the same JSON catalogs as #{default_locale}"

      Enum.each(default_catalogs, fn {filename, default_messages} ->
        messages = Map.fetch!(catalogs, filename)

        assert json_leaf_paths(messages) == json_leaf_paths(default_messages),
               "assets/app/locales/#{locale}/#{filename} must contain the same keys as #{default_locale}"

        assert json_translated?(messages),
               "assets/app/locales/#{locale}/#{filename} contains blank or non-string translations"
      end)
    end)
  end

  defp assert_complete_docs do
    default_locale = Locales.default_locale()
    default_keys = canonical_guide_keys(default_locale)

    assert MapSet.size(default_keys) > 0, "the default locale must publish documentation guides"

    Enum.each(Locales.locales(), fn locale ->
      guides = Guide.list_guides(locale)
      keys = Enum.map(guides, & &1.url_path)

      assert length(keys) == MapSet.size(MapSet.new(keys)),
             "documentation locale #{locale} contains duplicate canonical guide paths"

      assert MapSet.new(keys) == default_keys,
             "documentation locale #{locale} must publish the same canonical guide paths as #{default_locale}"
    end)
  end

  defp assert_complete_blog do
    locales = MapSet.new(Locales.locales())
    posts = Blog.list_compiled_posts()

    assert posts != [], "the public blog must contain at least one compiled post"

    posts
    |> Enum.group_by(& &1.translation_key)
    |> Enum.each(fn {translation_key, translations} ->
      translation_locales = Enum.map(translations, & &1.locale)
      publication_dates = translations |> Enum.map(& &1.published_on) |> Enum.uniq()

      assert length(translation_locales) == MapSet.size(MapSet.new(translation_locales)),
             "blog translation #{translation_key} contains duplicate locale variants"

      assert MapSet.new(translation_locales) == locales,
             "blog translation #{translation_key} must exist in every public locale"

      assert length(publication_dates) == 1,
             "blog translation #{translation_key} must use the same published_on date in every locale"
    end)
  end

  defp parse_po!(relative_path) do
    @project_root
    |> Path.join(relative_path)
    |> Expo.PO.parse_file!()
  end

  defp message_keys(messages), do: MapSet.new(messages, &message_key/1)

  defp message_key(%Singular{msgctxt: context, msgid: msgid}) do
    {:singular, to_text(context), to_text(msgid)}
  end

  defp message_key(%Plural{msgctxt: context, msgid: msgid, msgid_plural: plural}) do
    {:plural, to_text(context), to_text(msgid), to_text(plural)}
  end

  defp translated?(%Singular{msgstr: msgstr}, _catalog), do: present?(msgstr)

  defp translated?(%Plural{msgstr: msgstr}, catalog) do
    expected_indexes = plural_indexes(catalog)

    MapSet.new(Map.keys(msgstr)) == expected_indexes and
      Enum.all?(msgstr, fn {_index, translation} -> present?(translation) end)
  end

  defp plural_indexes(catalog) do
    [plural_forms] = Expo.Messages.get_header(catalog, "Plural-Forms")
    %{nplurals: count} = Expo.PluralForms.parse!(plural_forms)
    MapSet.new(0..(count - 1))
  end

  defp present?(iodata), do: String.trim(to_text(iodata)) != ""
  defp to_text(nil), do: ""
  defp to_text(iodata), do: IO.iodata_to_binary(iodata)

  defp vue_catalogs(locale) do
    @project_root
    |> Path.join("assets/app/locales/#{locale}/*.json")
    |> Path.wildcard()
    |> Map.new(fn path -> {Path.basename(path), path |> File.read!() |> Jason.decode!()} end)
  end

  defp json_leaf_paths(value), do: value |> json_leaf_paths([]) |> MapSet.new()

  defp json_leaf_paths(value, path) when is_map(value) do
    Enum.flat_map(value, fn {key, nested} -> json_leaf_paths(nested, path ++ [key]) end)
  end

  defp json_leaf_paths(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {nested, index} -> json_leaf_paths(nested, path ++ [index]) end)
  end

  defp json_leaf_paths(_value, path), do: [path]

  defp json_translated?(value) when is_map(value), do: Enum.all?(value, &json_entry_translated?/1)
  defp json_translated?(value) when is_list(value), do: Enum.all?(value, &json_translated?/1)
  defp json_translated?(value) when is_binary(value), do: String.trim(value) != ""
  defp json_translated?(_value), do: false

  defp json_entry_translated?({_key, value}), do: json_translated?(value)

  defp canonical_guide_keys(locale) do
    locale
    |> Guide.list_guides()
    |> MapSet.new(& &1.url_path)
  end
end
