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

  @default_locale "en"

  @doc "Lists published posts in reverse chronological order."
  def list_posts(locale \\ @default_locale) do
    today = Date.utc_today()

    @posts
    |> Enum.filter(&(&1.locale == locale && Date.compare(&1.published_on, today) != :gt))
    |> Enum.sort_by(& &1.published_on, {:desc, Date})
  end

  @doc "Gets a published post by slug."
  def get_post(slug, locale \\ @default_locale) when is_binary(slug) do
    Enum.find(list_posts(locale), &(&1.slug == slug))
  end
end
