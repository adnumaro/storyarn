defmodule Storyarn.Publication.LocalesTest do
  use ExUnit.Case, async: true

  alias Expo.Message
  alias Expo.Message.Plural
  alias Expo.Message.Singular
  alias Storyarn.Blog
  alias Storyarn.Docs.Guide
  alias Storyarn.Publication.Locales

  @project_root Path.expand("../../..", __DIR__)

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

  test "every published locale has a complete content surface" do
    assert_complete_gettext_catalogs()
    assert_complete_vue_catalogs()
    assert_complete_docs()
    assert_complete_blog()
  end

  # `.pot` and `.po` are both derived from the source tree, so comparing them to
  # each other cannot see a placeholder that only the source knows about. This is
  # the one check on the *contents* of a translation rather than its presence,
  # and it catches the failure `mix gettext.extract --merge` actively creates:
  # when a msgid changes, the merge copies the nearest neighbour's msgstr, and a
  # neighbour's placeholder set is not the new msgid's. `versioning.po` shipped
  # `"Before restore to v%{n}"` translated with `%{number}` — Gettext has nothing
  # to bind, so Spanish users read the literal `%{number}` on screen.
  #
  # Extraction freshness — `.pot` against source — is the third axis, and it
  # cannot live here: it needs a compiler pass. It runs in `mix precommit` and
  # `just quality-lint` as `mix gettext.extract --check-up-to-date`.
  test "no translation binds a placeholder its message never provides" do
    for locale <- Locales.localized_locales(),
        path <- gettext_catalogs(locale),
        message <- parse_po!(path).messages,
        {reason, key, provided, used} <- placeholder_faults(message) do
      flunk("""
      #{path} — #{reason}

          msgid       #{inspect(key)}
          provides    #{inspect(MapSet.to_list(provided))}
          translation #{inspect(MapSet.to_list(used))}

      Gettext substitutes by name. A placeholder the message never provides is
      printed verbatim to the user; one the translation drops silently loses the
      value the sentence was written to carry.
      """)
    end
  end

  defp gettext_catalogs(locale) do
    @project_root
    |> Path.join("priv/gettext/#{locale}/LC_MESSAGES/*.po")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @project_root))
  end

  defp gettext_domains do
    @project_root
    |> Path.join("priv/gettext/*.pot")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".pot"))
    |> Enum.sort()
  end

  defp assert_complete_gettext_catalogs do
    domains = gettext_domains()

    assert domains != [], "priv/gettext must publish at least one .pot template"

    Enum.each(Locales.locales(), fn locale ->
      catalogs =
        locale |> gettext_catalogs() |> Enum.map(&Path.basename(&1, ".po")) |> Enum.sort()

      assert catalogs == domains,
             "priv/gettext/#{locale}/LC_MESSAGES has no catalog for #{inspect(domains -- catalogs)} " <>
               "and carries an orphan one for #{inspect(catalogs -- domains)}. A domain with no " <>
               "catalog is a domain Gettext can only serve in English."
    end)

    Enum.each(domains, fn domain ->
      template = parse_po!("priv/gettext/#{domain}.pot")
      template_keys = message_keys(template.messages)

      Enum.each(
        Locales.locales(),
        &assert_complete_gettext_catalog(&1, domain, template_keys)
      )
    end)
  end

  # Runs over every domain, not just the public ones. It used to walk
  # `~w(public docs blog)` — 3 of the 19 `.pot` files — which left every
  # app-facing domain unguarded: `es/projects.po` had drifted to 63 messages
  # short of `projects.pot` with a green suite. The catalog workflow this
  # enforces is in `docs/conventions/domain-patterns.md`.
  defp assert_complete_gettext_catalog(locale, domain, template_keys) do
    relative_path = "priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po"
    catalog = parse_po!(relative_path)
    catalog_keys = message_keys(catalog.messages)

    assert catalog_keys == template_keys,
           "#{relative_path} has drifted from #{domain}.pot: " <>
             "#{MapSet.size(MapSet.difference(template_keys, catalog_keys))} message(s) the app can " <>
             "emit have no entry here and reach the user in English, and " <>
             "#{MapSet.size(MapSet.difference(catalog_keys, template_keys))} entry(ies) translate " <>
             "text no longer in the source. Run `mix gettext.extract --merge`."

    if locale == Locales.default_locale() do
      # `Gettext.Compiler` filters compiled messages on `obsolete` alone — it has
      # no notion of `fuzzy` at runtime — so whatever sits in a msgstr is what
      # ships. In the default locale a msgstr is therefore not a translation but
      # an override of the source string, and the merge writes those on its own:
      # `en/projects.po` served "Project Trash" for the msgid "Project name", and
      # `en/flows.po` answered "Could not update scene map." with "Could not
      # update node positions.". Empty is the convention here; Gettext falls back
      # to the msgid, which is already English.
      rewritten = Enum.filter(catalog.messages, &rewrites_source?/1)

      assert rewritten == [],
             "#{relative_path} overrides #{length(rewritten)} source string(s) with different " <>
               "English: " <>
               inspect(Enum.map(rewritten, &message_key/1)) <>
               ". Blank the msgstr so Gettext falls back to the msgid."
    else
      fuzzy = Enum.filter(catalog.messages, &Message.has_flag?(&1, "fuzzy"))

      assert fuzzy == [],
             "#{relative_path} ships #{length(fuzzy)} fuzzy translation(s): " <>
               inspect(Enum.map(fuzzy, &message_key/1)) <>
               ". A fuzzy entry is the merge's guess copied off a neighbouring msgid, and " <>
               "Gettext serves it to users with nothing to distinguish it from a reviewed one."

      untranslated = Enum.reject(catalog.messages, &translated?(&1, catalog))

      assert untranslated == [],
             "#{relative_path} leaves #{length(untranslated)} message(s) untranslated: " <>
               inspect(Enum.map(untranslated, &message_key/1)) <>
               ". An empty msgstr falls back to English mid-interface."
    end
  end

  defp rewrites_source?(%Singular{msgid: msgid, msgstr: msgstr}) do
    text = to_text(msgstr)
    text != "" and text != to_text(msgid)
  end

  defp rewrites_source?(%Plural{msgid: msgid, msgid_plural: plural, msgstr: msgstr}) do
    forms = [to_text(msgid), to_text(plural)]

    Enum.any?(msgstr, fn {_index, form} ->
      text = to_text(form)
      text != "" and text not in forms
    end)
  end

  # Returns [] for a healthy message. Plural messages are compared as a set
  # union, not per index: a form may legitimately hardcode the number it stands
  # for ("1 item"), so only dropping a placeholder from *every* form is a fault.
  defp placeholder_faults(%Singular{msgid: msgid, msgstr: msgstr}) do
    provided = placeholders(msgid)
    used = placeholders(msgstr)

    cond do
      MapSet.size(used) == 0 and to_text(msgstr) == "" -> []
      MapSet.equal?(provided, used) -> []
      true -> [{fault_reason(provided, used), to_text(msgid), provided, used}]
    end
  end

  defp placeholder_faults(%Plural{msgid: msgid, msgid_plural: plural, msgstr: msgstr}) do
    provided = MapSet.union(placeholders(msgid), placeholders(plural))
    used = msgstr |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union(placeholders(&1), &2))

    cond do
      MapSet.size(used) == 0 and Enum.all?(Map.values(msgstr), &(to_text(&1) == "")) -> []
      MapSet.equal?(provided, used) -> []
      true -> [{fault_reason(provided, used), to_text(msgid), provided, used}]
    end
  end

  defp fault_reason(provided, used) do
    unbound = MapSet.difference(used, provided)

    if MapSet.size(unbound) > 0 do
      "the translation uses #{inspect(MapSet.to_list(unbound))}, which the message never binds"
    else
      "the translation drops #{inspect(MapSet.to_list(MapSet.difference(provided, used)))}"
    end
  end

  defp placeholders(iodata) do
    ~r/%\{([^}]+)\}/
    |> Regex.scan(to_text(iodata))
    |> MapSet.new(fn [_full, name] -> name end)
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
