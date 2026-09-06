defmodule Storyarn.Flows.Editor.Commands.SequenceUpdate do
  @moduledoc false

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Repo

  @spec update_sequence(FlowNode.t(), map()) ::
          {:ok, FlowNode.t()} | {:error, Ecto.Changeset.t()}
  def update_sequence(%FlowNode{type: "sequence"} = node, attrs) do
    attrs = normalize_keys(attrs)
    node_attrs = Map.take(attrs, ["position_x", "position_y", "parent_id"])

    config_attrs = Map.take(attrs, ["name", "width", "height"])

    Repo.transaction(fn ->
      with {:ok, %{flow: flow, node: locked_node}} <-
             References.lock_active_node_for_write(node),
           :ok <- ensure_sequence(locked_node),
           parent_id = Map.get(node_attrs, "parent_id", locked_node.parent_id),
           {:ok, parent_id} <-
             References.lock_node_parent(
               flow.id,
               parent_id,
               locked_node.id
             ) do
        node_attrs = put_normalized_parent_id(node_attrs, parent_id)

        updated_node = update_sequence_node(locked_node, node_attrs)
        updated_config = update_sequence_config(locked_node, config_attrs)

        %{updated_node | sequence_config: updated_config}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp ensure_config_loaded(%FlowNode{sequence_config: %SequenceConfig{} = config}), do: config

  defp ensure_config_loaded(%FlowNode{id: id}), do: Repo.get_by!(SequenceConfig, flow_node_id: id)

  defp update_sequence_node(node, attrs) when map_size(attrs) == 0, do: node

  defp update_sequence_node(node, attrs) do
    case node |> FlowNode.update_changeset(attrs) |> Repo.update() do
      {:ok, node} -> node
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_sequence_config(node, attrs) when map_size(attrs) == 0 do
    ensure_config_loaded(node)
  end

  defp update_sequence_config(node, attrs) do
    case node
         |> ensure_config_loaded()
         |> SequenceConfig.update_changeset(attrs)
         |> Repo.update() do
      {:ok, config} -> config
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp ensure_sequence(%FlowNode{type: "sequence", deleted_at: nil}), do: :ok
  defp ensure_sequence(_node), do: {:error, :sequence_not_found}

  defp put_normalized_parent_id(node_attrs, parent_id) do
    if Map.has_key?(node_attrs, "parent_id"),
      do: Map.put(node_attrs, "parent_id", parent_id),
      else: node_attrs
  end
end
