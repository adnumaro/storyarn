defmodule Storyarn.References.RichTextMentions do
  @moduledoc false

  @mention_markup ~r/<[^>]*\bclass\s*=\s*["'](?:[^"']*\s)?mention(?:\s[^"']*)?["'][^>]*>/iu
  @unquoted_mention_markup ~r/<[^>]*\bclass\s*=\s*mention(?=[\s\/>])[^>]*>/iu

  @type mention :: %{type: String.t(), id: String.t()}
  @type parse_error ::
          {:invalid_html, term()}
          | {:invalid_mention, %{type: [String.t()], id: [String.t()]}}

  @doc false
  @spec html_candidates(term()) :: [String.t()]
  def html_candidates(value), do: collect_html_candidates(value, [])

  @doc false
  @spec extract_from_html(term()) :: {:ok, [mention()]} | {:error, parse_error()}
  def extract_from_html(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, document} ->
        document
        |> Floki.find(".mention")
        |> Enum.reduce_while({:ok, []}, &accumulate_mention/2)
        |> case do
          {:ok, mentions} -> {:ok, Enum.reverse(mentions)}
          {:error, _reason} = error -> error
        end

      {:error, reason} ->
        {:error, {:invalid_html, reason}}
    end
  end

  def extract_from_html(html), do: {:error, {:invalid_html, html}}

  defp collect_html_candidates(value, acc) when is_binary(value) do
    if Regex.match?(@mention_markup, value) or Regex.match?(@unquoted_mention_markup, value),
      do: [value | acc],
      else: acc
  end

  defp collect_html_candidates(value, acc) when is_list(value) do
    Enum.reduce(value, acc, &collect_html_candidates/2)
  end

  defp collect_html_candidates(value, acc) when is_map(value) do
    Enum.reduce(value, acc, fn {_key, nested}, nested_acc ->
      collect_html_candidates(nested, nested_acc)
    end)
  end

  defp collect_html_candidates(_value, acc), do: acc

  defp accumulate_mention(element, {:ok, mentions}) do
    type_attributes = attribute_values(element, "data-type")
    id_attributes = attribute_values(element, "data-id")

    case {type_attributes, id_attributes} do
      {[type], [id]} when type in ["sheet", "flow"] and is_binary(id) and byte_size(id) > 0 ->
        if String.trim(id) == "" do
          {:halt, invalid_mention(type_attributes, id_attributes)}
        else
          {:cont, {:ok, [%{type: type, id: id} | mentions]}}
        end

      _invalid_attributes ->
        {:halt, invalid_mention(type_attributes, id_attributes)}
    end
  end

  defp invalid_mention(type_attributes, id_attributes) do
    {:error, {:invalid_mention, %{type: type_attributes, id: id_attributes}}}
  end

  defp attribute_values({_tag, attributes, _children}, attribute_name) when is_list(attributes) do
    for {name, value} <- attributes, name == attribute_name, do: value
  end

  defp attribute_values(_element, _attribute_name), do: []
end
