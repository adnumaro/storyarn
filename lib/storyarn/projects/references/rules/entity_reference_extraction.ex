defmodule Storyarn.Projects.References.EntityReferenceExtraction do
  @moduledoc """
  Pure extraction and validation of entity references embedded in block values.

  Receipts retain their encoded IDs and source order. ID normalization is used
  only to reject values that cannot address a positive PostgreSQL bigint.
  """

  alias Storyarn.Projects.References.RichTextMentions

  @max_pg_bigint 9_223_372_036_854_775_807

  @spec extract_block_value_references(String.t(), term()) ::
          {:ok, [map()]} | {:error, term()}
  def extract_block_value_references("reference", value) when is_map(value) do
    target_type = reference_value(value, "target_type")
    target_id = reference_value(value, "target_id")

    case {normalize_optional_target_type(target_type), target_id} do
      {nil, id} when id in [nil, ""] ->
        {:ok, []}

      {type, id} when type in ["sheet", "flow"] and id not in [nil, ""] ->
        validate_block_reference(type, id, target_type)

      _invalid_pair ->
        {:error, {:invalid_project_reference, {:block, :value, target_type}, target_id}}
    end
  end

  def extract_block_value_references("rich_text", value) when is_map(value) do
    content = value["content"] || value[:content] || ""
    strict_mentions_from_html(content)
  end

  def extract_block_value_references(type, value) when type in ["reference", "rich_text"] do
    {:error, {:invalid_project_reference, {:block, :value, type}, value}}
  end

  def extract_block_value_references(_type, _value), do: {:ok, []}

  defp validate_block_reference(type, id, diagnostic_type) do
    case normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) ->
        {:ok, [%{type: type, id: id, context: "value"}]}

      _invalid_or_absent ->
        {:error, {:invalid_project_reference, {:block, :value, diagnostic_type}, id}}
    end
  end

  defp strict_mentions_from_html(content) when is_binary(content) do
    case RichTextMentions.extract_from_html(content) do
      {:ok, mentions} ->
        {:ok, Enum.map(mentions, &Map.put(&1, :context, "content"))}

      {:error, {:invalid_html, reason}} ->
        {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, reason}}

      {:error, {:invalid_mention, details}} ->
        invalid_mention_reference(details)
    end
  end

  defp strict_mentions_from_html(content) do
    {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, content}}
  end

  defp invalid_mention_reference(%{type: [type], id: [id]}) do
    {:error, {:invalid_project_reference, {:block, :content, type}, id}}
  end

  defp invalid_mention_reference(details) do
    {:error, {:invalid_project_reference, {:block, :content, :malformed_mention}, details}}
  end

  defp normalize_optional_target_type(nil), do: nil
  defp normalize_optional_target_type(""), do: nil
  defp normalize_optional_target_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_optional_target_type(type), do: type

  defp reference_value(value, key) do
    case Map.fetch(value, key) do
      {:ok, stored_value} -> stored_value
      :error -> Map.get(value, reference_atom_key(key))
    end
  end

  defp reference_atom_key("target_type"), do: :target_type
  defp reference_atom_key("target_id"), do: :target_id

  defp normalize_optional_id(nil), do: {:ok, nil}
  defp normalize_optional_id(""), do: {:ok, nil}

  defp normalize_optional_id(id) when is_integer(id) and id > 0 and id <= @max_pg_bigint, do: {:ok, id}

  defp normalize_optional_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 and parsed <= @max_pg_bigint -> {:ok, parsed}
      _other -> :error
    end
  end

  defp normalize_optional_id(_id), do: :error
end
