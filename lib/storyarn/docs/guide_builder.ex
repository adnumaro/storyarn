defmodule Storyarn.Docs.GuideBuilder do
  @moduledoc false

  def build(filename, attrs, body) do
    parts =
      filename
      |> Path.rootname()
      |> Path.split()

    [category, raw_slug] = Enum.take(parts, -2)
    slug = String.replace(raw_slug, ~r/^\d+-/, "")

    %{
      slug: slug,
      title: attrs[:title],
      category: category,
      category_label: attrs[:category_label],
      order: attrs[:order],
      description: attrs[:description],
      body: body
    }
  end
end
