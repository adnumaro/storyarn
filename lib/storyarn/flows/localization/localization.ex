defmodule Storyarn.Flows.Localization do
  @moduledoc """
  Capability boundary for Flow-localizable content and Localization commands.

  Flows owns the source vocabulary and word-count semantics. The Localization
  context owns extraction and the shared inventory; this boundary exposes only
  the commands required by Flow workflows.
  """

  alias Storyarn.Flows.ContentContract
  alias Storyarn.Flows.WordCount
  alias Storyarn.Localization, as: LocalizationOwner

  defdelegate localizable_node_types(), to: ContentContract
  defdelegate node_word_count(type, data), to: WordCount, as: :for_node_data
  # Flow snapshot build already owns a Project row lock. Preserve its historical
  # SHARE -> Flow -> advisory order instead of upgrading Project after Flow.
  def lock_inventory!(project_id), do: LocalizationOwner.lock_inventory_after_project_lock!(project_id)
  defdelegate extract_flow_node(node), to: LocalizationOwner
  defdelegate extract_flow_nodes(flow_id), to: LocalizationOwner

  defdelegate flow_node_texts_current_ids(nodes, project_id),
    to: LocalizationOwner

  defdelegate delete_flow_node_texts(node_id), to: LocalizationOwner
  defdelegate delete_flow_node_texts_for_flows(flow_ids), to: LocalizationOwner

  def purge_texts_for_sources("flow_node", source_ids), do: LocalizationOwner.purge_flow_node_texts(source_ids)
end
