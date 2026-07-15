defmodule Storyarn.Publication.HtmlLinkLocalizer do
  @moduledoc false

  alias Storyarn.Publication.PathLocalizer

  @spec localize_navigation(String.t(), String.t()) :: String.t()
  def localize_navigation(body, locale) do
    case Floki.parse_fragment(body) do
      {:ok, nodes} ->
        nodes
        |> Floki.traverse_and_update(&localize_link(&1, locale))
        |> Floki.raw_html()

      _error ->
        body
    end
  end

  defp localize_link({"a", attrs, children}, locale) do
    href = attribute_value(attrs, "href")

    if internal_path?(href) do
      attrs = put_attribute(attrs, "href", PathLocalizer.localize(href, locale))
      {"a", maybe_enable_live_navigation(attrs), children}
    else
      {"a", attrs, children}
    end
  end

  defp localize_link(node, _locale), do: node

  defp internal_path?("/" <> rest), do: not String.starts_with?(rest, "/")
  defp internal_path?(_href), do: false

  defp maybe_enable_live_navigation(attrs) do
    if live_navigation_safe?(attrs) do
      attrs
      |> put_attribute("data-phx-link", "redirect")
      |> put_attribute("data-phx-link-state", "push")
    else
      attrs
    end
  end

  defp live_navigation_safe?(attrs) do
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
