defmodule Storyarn.Blog.Post do
  @moduledoc """
  Compile-time publisher and query module for Storyarn blog posts.
  """

  use NimblePublisher,
    build: Storyarn.Blog.PostBuilder,
    from: "priv/blog/**/*.md",
    as: :posts,
    highlighters: [:makeup_elixir],
    earmark_options: %Earmark.Options{gfm_tables: true}

  @default_locale Storyarn.Publication.Locales.default_locale()

  for {{locale, slug}, posts} <- Enum.group_by(@posts, &{&1.locale, &1.slug}),
      length(posts) > 1 do
    raise ArgumentError,
          "duplicate blog slug #{inspect(slug)} for locale #{inspect(locale)}"
  end

  for {{translation_key, locale}, posts} <-
        Enum.group_by(@posts, &{&1.translation_key, &1.locale}),
      length(posts) > 1 do
    raise ArgumentError,
          "duplicate blog translation #{inspect(translation_key)} for locale #{inspect(locale)}"
  end

  @doc "Returns the locale used by unprefixed blog URLs."
  def default_locale, do: @default_locale

  @doc "Lists every locale that currently has a published post."
  def published_locales do
    list_published_posts()
    |> Enum.map(& &1.locale)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1 != @default_locale, &1})
  end

  @doc "Lists every post compiled from Markdown, including scheduled posts."
  def list_compiled_posts do
    Enum.sort_by(@posts, & &1.published_on, {:desc, Date})
  end

  @doc "Lists posts visible on the given date across all locales."
  def list_published_posts(as_of \\ Date.utc_today())

  def list_published_posts(%Date{} = as_of) do
    Enum.filter(list_compiled_posts(), &(Date.compare(&1.published_on, as_of) != :gt))
  end

  @doc "Lists every currently published post across locales."
  def list_all_posts, do: list_published_posts()

  @doc "Lists published posts in reverse chronological order."
  def list_posts(locale \\ @default_locale) do
    Enum.filter(list_published_posts(), &(&1.locale == locale))
  end

  @doc "Gets a published post by slug."
  def get_post(slug, locale \\ @default_locale) when is_binary(slug) do
    Enum.find(list_posts(locale), &(&1.slug == slug))
  end

  @doc "Lists the published language variants of one editorial article."
  def list_translations(translation_key) when is_binary(translation_key) do
    list_published_posts()
    |> Enum.filter(&(&1.translation_key == translation_key))
    |> Enum.sort_by(&{&1.locale != @default_locale, &1.locale})
  end

  @doc "Gets one language variant by its stable translation key."
  def get_translation(translation_key, locale) when is_binary(translation_key) and is_binary(locale) do
    Enum.find(list_translations(translation_key), &(&1.locale == locale))
  end
end
