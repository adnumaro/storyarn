defmodule StoryarnWeb.PublicURLs do
  @moduledoc """
  Canonical paths and language relationships for Storyarn's public pages.

  The default locale keeps the existing unprefixed URLs. Every other public
  locale receives a stable prefix, so one indexable URL always renders one
  language.
  """

  alias Storyarn.Localization.Languages
  alias Storyarn.Publication.Locales, as: PublicLocales
  alias Storyarn.Publication.PathLocalizer
  alias StoryarnWeb.Layouts

  @public_roots ~w(contact privacy terms docs blog)
  @known_gettext_locales Gettext.known_locales(Storyarn.Gettext)

  @spec home_path(String.t()) :: String.t()
  def home_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/")

  @spec contact_path(String.t()) :: String.t()
  def contact_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/contact")

  @spec privacy_path(String.t()) :: String.t()
  def privacy_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/privacy")

  @spec terms_path(String.t()) :: String.t()
  def terms_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/terms")

  @spec docs_index_path(String.t()) :: String.t()
  def docs_index_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/docs")

  @spec docs_path(map()) :: String.t()
  def docs_path(%{locale: locale} = guide), do: docs_path(locale, guide)

  def docs_path(%{category: category, path: path}), do: docs_path(PublicLocales.default_locale(), category, path)

  @spec docs_path(String.t(), map()) :: String.t()
  def docs_path(locale, %{category: category, path: path}), do: docs_path(locale, category, path)

  @spec docs_path(String.t(), String.t()) :: String.t()
  def docs_path(category, path), do: docs_path(PublicLocales.default_locale(), category, path)

  @spec docs_path(String.t(), String.t(), String.t() | [String.t()]) :: String.t()
  def docs_path(locale, category, path) do
    suffix = path |> path_segments() |> Enum.join("/")
    localized_path(locale, "/docs/#{trim_segment(category)}/#{suffix}")
  end

  @doc "Returns the canonical blog index for a public locale."
  @spec blog_index_path(String.t()) :: String.t()
  def blog_index_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/blog")

  @spec blog_post_path(map()) :: String.t()
  def blog_post_path(%{locale: locale, slug: slug}), do: blog_post_path(locale, slug)

  @spec blog_post_path(String.t(), String.t()) :: String.t()
  def blog_post_path(locale, slug), do: localized_path(locale, "/blog/#{trim_segment(slug)}")

  @doc "Adds an explicit locale handoff to a non-indexable destination."
  @spec locale_handoff_path(String.t(), String.t()) :: String.t()
  def locale_handoff_path(path, locale) when is_binary(path) do
    locale = validate_gettext_locale!(locale)
    uri = URI.parse(path)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("locale", locale)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  @doc "Extracts a public locale from a URI. Non-public paths return nil."
  @spec locale_from_uri(String.t() | URI.t()) :: String.t() | nil
  def locale_from_uri(%URI{path: path}), do: locale_from_path(path || "")

  def locale_from_uri(uri) when is_binary(uri) do
    uri
    |> URI.parse()
    |> locale_from_uri()
  end

  def locale_from_uri(_uri), do: nil

  @doc "Extracts the authoritative locale from a canonical public path."
  @spec locale_from_path(String.t()) :: String.t() | nil
  def locale_from_path(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> locale_from_segments()
  end

  def locale_from_path(_path), do: nil

  @doc """
  Moves a local path to the requested locale while preserving query and fragment.

  Existing public locale prefixes are replaced, including the non-canonical
  default prefix used by redirect aliases.
  """
  @spec localize_path(String.t(), String.t()) :: String.t()
  defdelegate localize_path(path, locale), to: PathLocalizer, as: :localize

  @doc "Builds language-switcher entries from `{locale, path}` pairs."
  @spec language_links([{String.t(), String.t()}]) :: [map()]
  def language_links(locale_paths) when is_list(locale_paths) do
    Enum.map(locale_paths, fn {locale, path} ->
      locale = validate_locale!(locale)
      language_tag = PublicLocales.language_tag(locale)
      language = Languages.get(language_tag)

      %{
        locale: locale,
        language_tag: language_tag,
        label: if(language, do: language.native, else: String.upcase(language_tag)),
        path: path
      }
    end)
  end

  @doc "Builds absolute reciprocal hreflang entries, including x-default."
  @spec alternate_links([{String.t(), String.t()}]) :: [map()]
  def alternate_links(locale_paths) when is_list(locale_paths) do
    links = language_links(locale_paths)

    alternates =
      Enum.map(links, fn link ->
        %{hreflang: link.language_tag, href: Layouts.absolute_url(link.path)}
      end)

    case Enum.find(links, &(&1.locale == PublicLocales.default_locale())) do
      nil -> alternates
      default -> alternates ++ [%{hreflang: "x-default", href: Layouts.absolute_url(default.path)}]
    end
  end

  defp localized_path(locale, path), do: PathLocalizer.localized_path(locale, path)

  defp locale_from_segments([]), do: PublicLocales.default_locale()

  defp locale_from_segments([segment]) do
    case PublicLocales.localized_locale_from_path_segment(segment) do
      nil -> if(segment in @public_roots, do: PublicLocales.default_locale())
      locale -> locale
    end
  end

  defp locale_from_segments([segment, root | _rest]) when root in @public_roots do
    PublicLocales.localized_locale_from_path_segment(segment)
  end

  defp locale_from_segments([root | _rest]) when root in @public_roots, do: PublicLocales.default_locale()

  defp locale_from_segments(_segments), do: nil

  defp path_segments(path) when is_list(path), do: Enum.map(path, &trim_segment/1)

  defp path_segments(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map(&trim_segment/1)
  end

  defp trim_segment(segment) when is_binary(segment), do: String.trim(segment, "/")

  defp validate_locale!(locale) do
    if PublicLocales.valid?(locale) do
      locale
    else
      raise ArgumentError, "unsupported public locale: #{inspect(locale)}"
    end
  end

  defp validate_gettext_locale!(locale) when locale in @known_gettext_locales, do: locale

  defp validate_gettext_locale!(locale) do
    raise ArgumentError, "unsupported Gettext locale: #{inspect(locale)}"
  end
end
