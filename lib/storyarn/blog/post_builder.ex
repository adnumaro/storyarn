defmodule Storyarn.Blog.PostBuilder do
  @moduledoc false

  alias Storyarn.Shared.HtmlUtils

  @words_per_minute 200
  @default_image "/images/landing/storyarn-lab-hero.webp"

  def build(filename, attrs, body) do
    {locale, published_on, slug} = publication_data!(filename)
    body = body |> HtmlUtils.add_heading_ids() |> add_internal_live_navigation()

    %{
      id: slug,
      slug: slug,
      locale: locale,
      title: Map.fetch!(attrs, :title),
      seo_title: Map.get(attrs, :seo_title, Map.fetch!(attrs, :title)),
      description: Map.fetch!(attrs, :description),
      author: Map.get(attrs, :author, "Storyarn Team"),
      author_url: Map.get(attrs, :author_url, "/"),
      image: Map.get(attrs, :image, @default_image),
      image_alt: Map.get(attrs, :image_alt, Map.fetch!(attrs, :title)),
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

  defp add_internal_live_navigation(body) do
    case Floki.parse_fragment(body) do
      {:ok, nodes} ->
        nodes
        |> Floki.traverse_and_update(&mark_internal_link/1)
        |> Floki.raw_html()

      _ ->
        body
    end
  end

  defp mark_internal_link({"a", attrs, children}) do
    href = attribute_value(attrs, "href")

    if internal_path?(href) and navigation_safe?(attrs) do
      attrs =
        attrs
        |> put_attribute("data-phx-link", "redirect")
        |> put_attribute("data-phx-link-state", "push")

      {"a", attrs, children}
    else
      {"a", attrs, children}
    end
  end

  defp mark_internal_link(node), do: node

  defp internal_path?("/" <> rest), do: not String.starts_with?(rest, "/")
  defp internal_path?(_href), do: false

  defp navigation_safe?(attrs) do
    Enum.all?(["download", "target", "data-live-link-exempt"], fn name ->
      is_nil(attribute_value(attrs, name))
    end)
  end

  defp attribute_value(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp put_attribute(attrs, name, value), do: List.keystore(attrs, name, 0, {name, value})
end
