defmodule Storyarn.Blog.PostBuilder do
  @moduledoc false

  alias Storyarn.Shared.HtmlUtils

  @words_per_minute 200
  @default_image "/images/landing/storyarn-lab-hero.webp"

  def build(filename, attrs, body) do
    {locale, published_on, slug} = publication_data!(filename)
    body = HtmlUtils.add_heading_ids(body)

    %{
      id: slug,
      slug: slug,
      locale: locale,
      title: Map.fetch!(attrs, :title),
      description: Map.fetch!(attrs, :description),
      author: Map.get(attrs, :author, "Storyarn Team"),
      author_url: Map.get(attrs, :author_url, "/"),
      image: Map.get(attrs, :image, @default_image),
      tags: Map.get(attrs, :tags, []),
      published_on: published_on,
      updated_on: updated_on!(attrs[:updated_on], published_on),
      reading_time: reading_time(body),
      body: body
    }
  end

  defp updated_on!(value, published_on) do
    updated_on = date_attribute!(value, published_on, :updated_on)

    if Date.before?(updated_on, published_on) do
      raise ArgumentError,
            "blog post updated_on cannot be earlier than its publication date"
    end

    updated_on
  end

  defp date_attribute!(nil, default, _attribute), do: default
  defp date_attribute!(%Date{} = date, _default, _attribute), do: date

  defp date_attribute!(value, _default, _attribute) when is_binary(value) do
    Date.from_iso8601!(value)
  end

  defp date_attribute!(value, _default, attribute) do
    raise ArgumentError,
          "blog post #{attribute} must be an ISO date, got: #{inspect(value)}"
  end

  defp publication_data!(filename) do
    parts = filename |> Path.rootname() |> Path.split()

    case Enum.drop_while(parts, &(&1 != "blog")) do
      ["blog", locale, dated_slug] ->
        parse_dated_slug!(filename, locale, dated_slug)

      _ ->
        raise ArgumentError,
              "blog posts must live at priv/blog/<locale>/YYYY-MM-DD-<slug>.md, got: #{filename}"
    end
  end

  defp parse_dated_slug!(filename, locale, dated_slug) do
    case Regex.run(~r/^(\d{4}-\d{2}-\d{2})-(.+)$/, dated_slug) do
      [_, date, slug] ->
        {locale, Date.from_iso8601!(date), slug}

      _ ->
        raise ArgumentError,
              "blog post filenames must start with an ISO date, got: #{filename}"
    end
  end

  defp reading_time(body) do
    max(1, ceil(HtmlUtils.word_count(body) / @words_per_minute))
  end
end
