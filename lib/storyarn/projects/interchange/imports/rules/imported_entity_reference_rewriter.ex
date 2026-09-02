defmodule Storyarn.Projects.Imports.ImportedEntityReferenceRewriter do
  @moduledoc """
  Validates and rewrites entity IDs embedded in imported JSON payloads.

  Top-level Sheet, Flow, and Scene IDs are remapped by the materializer.
  Reference blocks and HTML mentions carry those IDs inside JSON, so they must
  follow the same mapping — including when `:skip` reuses an active target root.
  """

  alias Storyarn.Projects.References

  @error :import_reference_contract_mismatch

  @spec validate(map()) :: :ok | {:error, :import_reference_contract_mismatch}
  def validate(data) when is_map(data) do
    target_ids = imported_target_ids(data)

    with :ok <- validate_block_references(data, target_ids),
         :ok <- validate_flow_node_mentions(data, target_ids) do
      validate_scene_zone_targets(data, target_ids)
    end
  end

  def validate(_data), do: {:error, @error}

  @spec remap_block_value(String.t(), term(), map()) ::
          {:ok, term()} | {:error, :import_reference_contract_mismatch}
  def remap_block_value("reference", value, id_map) when is_map(value) do
    case References.extract_block_value_references("reference", value) do
      {:ok, []} ->
        {:ok, value}

      {:ok, [%{type: type, id: source_id}]} ->
        with {:ok, target_id} <- fetch_target_id(id_map, type, source_id) do
          {:ok,
           value
           |> Map.delete(:target_id)
           |> Map.put("target_id", target_id)}
        end

      _invalid_or_ambiguous ->
        {:error, @error}
    end
  end

  def remap_block_value("reference", _value, _id_map), do: {:error, @error}

  def remap_block_value("rich_text", value, id_map) when is_map(value) do
    content = value["content"] || value[:content] || ""

    with {:ok, content} <- remap_html(content, id_map) do
      {:ok,
       value
       |> Map.delete(:content)
       |> Map.put("content", content)}
    end
  end

  def remap_block_value("rich_text", _value, _id_map), do: {:error, @error}
  def remap_block_value(_type, value, _id_map), do: {:ok, value}

  @spec remap_flow_node_data(map(), map()) ::
          {:ok, map()} | {:error, :import_reference_contract_mismatch}
  def remap_flow_node_data(data, id_map) when is_map(data), do: remap_mentions(data, id_map)
  def remap_flow_node_data(_data, _id_map), do: {:error, @error}

  @spec mentions?(term()) :: boolean()
  def mentions?(value), do: References.rich_text_html_candidates(value) != []

  defp validate_block_references(data, target_ids) do
    data
    |> imported_blocks()
    |> Enum.reduce_while(:ok, fn
      %{"type" => type} = block, :ok when type in ["reference", "rich_text"] ->
        case References.extract_block_value_references(type, block["value"] || %{}) do
          {:ok, references} -> continue_if_valid_references(references, target_ids)
          {:error, _reason} -> {:halt, {:error, @error}}
        end

      block, :ok when is_map(block) ->
        {:cont, :ok}

      _invalid_block, :ok ->
        {:halt, {:error, @error}}
    end)
  end

  defp validate_flow_node_mentions(data, target_ids) do
    data
    |> imported_flow_node_data()
    |> Enum.flat_map(&References.rich_text_html_candidates/1)
    |> Enum.reduce_while(:ok, fn html, :ok ->
      case References.extract_block_value_references("rich_text", %{"content" => html}) do
        {:ok, references} -> continue_if_valid_references(references, target_ids)
        {:error, _reason} -> {:halt, {:error, @error}}
      end
    end)
  end

  defp validate_scene_zone_targets(data, target_ids) do
    data["scenes"]
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn
      scene, :ok when is_map(scene) ->
        case scene["zones"] do
          nil -> {:cont, :ok}
          zones when is_list(zones) -> continue_if_valid_zones(zones, target_ids)
          _invalid_zones -> {:halt, {:error, @error}}
        end

      _invalid_scene, :ok ->
        {:cont, :ok}
    end)
  end

  defp continue_if_valid_zones(zones, target_ids) do
    zones
    |> Enum.reduce_while(:ok, fn
      zone, :ok when is_map(zone) ->
        action_type = zone["action_type"]
        type = zone["target_type"]
        id = zone["target_id"]

        cond do
          action_type not in [nil, "action"] ->
            {:cont, :ok}

          type in ["sheet", "flow", "scene"] and
              known_target?(%{type: type, id: id}, target_ids) ->
            {:cont, :ok}

          type in ["sheet", "flow", "scene"] ->
            {:halt, {:error, @error}}

          true ->
            {:cont, :ok}
        end

      _invalid_zone, :ok ->
        {:halt, {:error, @error}}
    end)
    |> case do
      :ok -> {:cont, :ok}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp continue_if_valid_references(references, target_ids) do
    if Enum.all?(references, &known_target?(&1, target_ids)),
      do: {:cont, :ok},
      else: {:halt, {:error, @error}}
  end

  defp known_target?(%{type: type, id: source_id}, target_ids) do
    with {:ok, entity_type} <- entity_type(type),
         {:ok, canonical_id} <- canonical_id(source_id) do
      target_ids
      |> Map.fetch!(entity_type)
      |> MapSet.member?(canonical_id)
    else
      _invalid -> false
    end
  end

  defp known_target?(_reference, _target_ids), do: false

  defp imported_target_ids(data) do
    %{
      sheet: root_ids(data["sheets"]),
      flow: root_ids(data["flows"]),
      scene: root_ids(data["scenes"])
    }
  end

  defp root_ids(entities) do
    entities
    |> List.wrap()
    |> Enum.reduce(MapSet.new(), fn
      %{"id" => id}, ids ->
        case canonical_id(id) do
          {:ok, canonical_id} -> MapSet.put(ids, canonical_id)
          :error -> ids
        end

      _invalid_entity, ids ->
        ids
    end)
  end

  defp imported_blocks(data) do
    data["sheets"]
    |> List.wrap()
    |> Enum.flat_map(fn
      sheet when is_map(sheet) -> List.wrap(sheet["blocks"])
      _invalid_sheet -> []
    end)
  end

  defp imported_flow_node_data(data) do
    data["flows"]
    |> List.wrap()
    |> Enum.flat_map(fn
      flow when is_map(flow) -> List.wrap(flow["nodes"])
      _invalid_flow -> []
    end)
    |> Enum.map(fn
      node when is_map(node) -> node["data"] || %{}
      _invalid_node -> %{}
    end)
  end

  defp remap_mentions(value, id_map) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, nested}, {:ok, remapped} ->
      case remap_mentions(nested, id_map) do
        {:ok, nested} -> {:cont, {:ok, Map.put(remapped, key, nested)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_mentions(value, id_map) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn nested, {:ok, remapped} ->
      case remap_mentions(nested, id_map) do
        {:ok, nested} -> {:cont, {:ok, [nested | remapped]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remapped} -> {:ok, Enum.reverse(remapped)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_mentions(value, id_map) when is_binary(value) do
    if mentions?(value), do: remap_html(value, id_map), else: {:ok, value}
  end

  defp remap_mentions(value, _id_map), do: {:ok, value}

  defp remap_html(html, id_map) when is_binary(html) do
    with {:ok, _references} <- References.extract_block_value_references("rich_text", %{"content" => html}),
         {:ok, document} <- Floki.parse_fragment(html),
         {:ok, document} <- remap_mention_nodes(document, id_map) do
      {:ok, Floki.raw_html(document)}
    else
      {:error, _reason} -> {:error, @error}
    end
  end

  defp remap_html(_html, _id_map), do: {:error, @error}

  defp remap_mention_nodes(nodes, id_map) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, remapped} ->
      case remap_mention_node(node, id_map) do
        {:ok, node} -> {:cont, {:ok, [node | remapped]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remapped} -> {:ok, Enum.reverse(remapped)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_mention_node({tag, attributes, children}, id_map)
       when is_binary(tag) and is_list(attributes) and is_list(children) do
    with {:ok, attributes} <- remap_mention_attributes(attributes, id_map),
         {:ok, children} <- remap_mention_nodes(children, id_map) do
      {:ok, {tag, attributes, children}}
    end
  end

  defp remap_mention_node(node, _id_map), do: {:ok, node}

  defp remap_mention_attributes(attributes, id_map) do
    if mention_attributes?(attributes) do
      type = attribute_value(attributes, "data-type")
      source_id = attribute_value(attributes, "data-id")

      with {:ok, target_id} <- fetch_target_id(id_map, type, source_id) do
        {:ok, List.keystore(attributes, "data-id", 0, {"data-id", Integer.to_string(target_id)})}
      end
    else
      {:ok, attributes}
    end
  end

  defp mention_attributes?(attributes) do
    attributes
    |> attribute_value("class")
    |> to_string()
    |> String.split()
    |> Enum.member?("mention")
  end

  defp attribute_value(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp fetch_target_id(id_map, type, source_id) do
    with {:ok, entity_type} <- entity_type(type),
         {:ok, canonical_id} <- canonical_id(source_id) do
      case find_mapped_target(id_map, entity_type, source_id, canonical_id) do
        {:ok, _target_id} = found -> found
        nil -> {:error, @error}
      end
    else
      _invalid -> {:error, @error}
    end
  end

  defp find_mapped_target(id_map, entity_type, source_id, canonical_id) do
    entity_type
    |> mapping_candidates(source_id, canonical_id)
    |> Enum.find_value(fn key -> mapped_target(id_map, key) end)
  end

  defp mapped_target(id_map, key) do
    case Map.fetch(id_map, key) do
      {:ok, target_id} when is_integer(target_id) and target_id > 0 -> {:ok, target_id}
      _missing -> nil
    end
  end

  defp mapping_candidates(entity_type, source_id, canonical_id) do
    parsed_id = String.to_integer(canonical_id)

    Enum.uniq([{entity_type, source_id}, {entity_type, canonical_id}, {entity_type, parsed_id}])
  end

  defp entity_type("sheet"), do: {:ok, :sheet}
  defp entity_type("flow"), do: {:ok, :flow}
  defp entity_type("scene"), do: {:ok, :scene}
  defp entity_type(_type), do: :error

  defp canonical_id(id) when is_integer(id) and id > 0, do: {:ok, Integer.to_string(id)}

  defp canonical_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, Integer.to_string(parsed)}
      _invalid -> :error
    end
  end

  defp canonical_id(_id), do: :error
end
