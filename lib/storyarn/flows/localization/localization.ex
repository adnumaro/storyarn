defmodule Storyarn.Flows.Localization do
  @moduledoc """
  Capability boundary for Flow-localizable content and its inventory projection.

  Flows owns the source vocabulary and extraction semantics. The shared SQL
  inventory remains an implementation detail during this code-isolation phase.
  """

  alias Storyarn.Flows.ContentContract
  alias Storyarn.Flows.LocalizationProjection
  alias Storyarn.Flows.WordCount

  defdelegate localizable_node_types(), to: ContentContract
  defdelegate node_word_count(type, data), to: WordCount, as: :for_node_data
  defdelegate lock_inventory!(project_id), to: LocalizationProjection
  defdelegate extract_flow_node(node), to: LocalizationProjection
  defdelegate extract_flow_nodes(flow_id), to: LocalizationProjection

  defdelegate flow_node_texts_current_ids(nodes, project_id),
    to: LocalizationProjection

  defdelegate delete_flow_node_texts(node_id), to: LocalizationProjection
  defdelegate delete_flow_node_texts_for_flows(flow_ids), to: LocalizationProjection
  defdelegate purge_texts_for_sources(source_type, source_ids), to: LocalizationProjection
end
