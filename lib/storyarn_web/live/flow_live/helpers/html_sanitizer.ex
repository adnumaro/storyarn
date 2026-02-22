defmodule StoryarnWeb.FlowLive.Helpers.HtmlSanitizer do
  @moduledoc false

  @allowed_tags ~w(p br em strong b i u s span a ul ol li blockquote code pre sub sup del h1 h2 h3 h4 h5 h6 div)
  @safe_uri_schemes ~w(http: https: mailto: tel: #)

  def sanitize_html(""), do: ""

  def sanitize_html(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        tree |> strip_unsafe_nodes() |> Floki.raw_html()

      _ ->
        Phoenix.HTML.html_escape(html) |> Phoenix.HTML.safe_to_string()
    end
  end

  def sanitize_html(_), do: ""

  defp strip_unsafe_nodes(nodes) when is_list(nodes),
    do: Enum.flat_map(nodes, &strip_unsafe_node/1)

  defp strip_unsafe_node({tag, attrs, children}) do
    if tag in @allowed_tags do
      safe_attrs = Enum.reject(attrs, fn {k, v} -> unsafe_attr?(k, v) end)
      [{tag, safe_attrs, strip_unsafe_nodes(children)}]
    else
      strip_unsafe_nodes(children)
    end
  end

  defp strip_unsafe_node(text) when is_binary(text), do: [text]
  defp strip_unsafe_node({:comment, _}), do: []
  defp strip_unsafe_node(_), do: []

  defp unsafe_attr?(name, value) when is_binary(name) do
    lower_name = String.downcase(name)

    cond do
      String.starts_with?(lower_name, "on") ->
        true

      lower_name in ~w(style srcdoc formaction) ->
        true

      lower_name in ~w(href src action) and is_binary(value) ->
        not safe_uri?(value)

      true ->
        false
    end
  end

  defp unsafe_attr?(_, _), do: false

  defp safe_uri?(value) do
    trimmed = value |> String.trim() |> String.downcase()

    # Empty or relative URIs are safe
    trimmed == "" or
      not String.contains?(trimmed, ":") or
      Enum.any?(@safe_uri_schemes, &String.starts_with?(trimmed, &1))
  end
end
