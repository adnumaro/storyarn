defmodule Storyarn.Ideation.Ideas.Rules.Content do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Platform.Shared.HtmlSanitizer

  @tags ~w(p br em strong b i u s span ul ol li blockquote code pre sub sup del h2 h3)
  @max_bytes 64_000
  # The mochiweb tokenizer behind Floki and HtmlSanitizer drops whitespace-only
  # text nodes, so "<strong>a</strong> <em>b</em>" would be stored as "ab".
  # A private-use character survives both parsers and is restored in the tree.
  @inline_space "\uE000"

  def validate_title(changeset) do
    case fetch_change(changeset, :title) do
      {:ok, title} when is_binary(title) ->
        if String.valid?(title),
          do: put_change(changeset, :title, String.trim(title)),
          else: add_error(changeset, :title, "must be valid text")

      _ ->
        changeset
    end
  end

  def validate_body(changeset) do
    case fetch_change(changeset, :body) do
      {:ok, body} when is_binary(body) and byte_size(body) <= @max_bytes ->
        normalize_body(changeset, body)

      {:ok, body} when is_binary(body) ->
        add_error(changeset, :body, "must be at most %{count} bytes", count: @max_bytes)

      _ ->
        changeset
    end
  end

  defp normalize_body(changeset, body) do
    with true <- String.valid?(body),
         {:ok, parsed} <- Floki.parse_fragment(HtmlSanitizer.sanitize_html(protect_inline_spaces(body))),
         tree = restore_inline_spaces(parsed),
         true <- supported?(tree, 0),
         false <- tree |> Floki.text() |> String.replace("\u00a0", " ") |> String.trim() == "" do
      put_change(changeset, :body, tree |> strip_attributes() |> Floki.raw_html())
    else
      _ -> add_error(changeset, :body, "must contain text with supported formatting and no attachments")
    end
  end

  # Input never legitimately contains the private-use marker; drop it so it
  # cannot forge a separator. Only spaces/tabs between tags are protected: a
  # newline between blocks carries no text and keeps being discarded.
  defp protect_inline_spaces(body) do
    body
    |> String.replace(@inline_space, "")
    |> String.replace(~r/>[ \t]+</, ">#{@inline_space}<")
  end

  defp restore_inline_spaces(nodes) do
    Enum.map(nodes, fn
      {tag, attrs, children} -> {tag, attrs, restore_inline_spaces(children)}
      text when is_binary(text) -> String.replace(text, @inline_space, " ")
      other -> other
    end)
  end

  defp supported?(_nodes, depth) when depth > 16, do: false
  defp supported?(nodes, depth), do: Enum.all?(nodes, &supported_node?(&1, depth))
  defp supported_node?(text, _depth) when is_binary(text), do: true
  defp supported_node?({tag, _attrs, children}, depth), do: tag in @tags and supported?(children, depth + 1)
  defp supported_node?(_, _depth), do: false

  defp strip_attributes(nodes) do
    Enum.map(nodes, fn
      {tag, _attrs, children} -> {tag, [], strip_attributes(children)}
      text -> text
    end)
  end
end
