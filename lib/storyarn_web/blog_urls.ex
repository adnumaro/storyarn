defmodule StoryarnWeb.BlogURLs do
  @moduledoc """
  Canonical paths and language relationships for the public blog.

  English keeps the unprefixed URL. Every other published locale uses a
  locale-prefixed URL so crawlers and readers always receive one language per
  address.
  """

  alias Storyarn.Blog
  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  def index_path(locale \\ Blog.default_locale()) do
    published_locale =
      if locale in published_public_locales(), do: locale, else: PublicLocales.default_locale()

    PublicURLs.blog_index_path(published_locale)
  end

  def post_path(%{locale: locale, slug: slug}), do: post_path(locale, slug)
  def post_path(locale, slug), do: PublicURLs.blog_post_path(locale, slug)

  def locale_from_uri(uri) when is_binary(uri) do
    uri |> URI.parse() |> Map.get(:path, "") |> locale_from_path()
  end

  def locale_from_path(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      ["blog" | _rest] ->
        validate_published_locale(PublicLocales.default_locale())

      [path_segment, "blog" | _rest] ->
        path_segment
        |> PublicLocales.locale_from_path_segment()
        |> validate_published_locale()

      _other ->
        nil
    end
  end

  def index_language_links do
    published_public_locales()
    |> Enum.map(&{&1, index_path(&1)})
    |> PublicURLs.language_links()
  end

  def post_language_links(post) do
    post.translation_key
    |> Blog.list_translations()
    |> Enum.filter(&PublicLocales.valid?(&1.locale))
    |> Enum.map(&{&1.locale, post_path(&1)})
    |> PublicURLs.language_links()
  end

  def index_alternate_links do
    published_public_locales()
    |> Enum.map(&{&1, index_path(&1)})
    |> PublicURLs.alternate_links()
  end

  def post_alternate_links(post) do
    post
    |> then(&Blog.list_translations(&1.translation_key))
    |> Enum.filter(&PublicLocales.valid?(&1.locale))
    |> Enum.map(&{&1.locale, post_path(&1)})
    |> PublicURLs.alternate_links()
  end

  defp validate_published_locale(locale) do
    if locale in published_public_locales(), do: locale
  end

  defp published_public_locales do
    Enum.filter(Blog.published_locales(), &PublicLocales.valid?/1)
  end
end
