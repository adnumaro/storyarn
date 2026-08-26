defmodule Storyarn.Flows.AI do
  @moduledoc """
  Public capability boundary for Flow-specific AI context construction.

  Provider policy and execution remain in `Storyarn.AI`; this slice owns the
  Flow vocabulary, bounded reads and source locks used to build deterministic
  context packages.
  """

  alias Storyarn.Flows.AI.ContextContract
  alias Storyarn.Flows.AI.DialogueContext
  alias Storyarn.Flows.AI.FlowNeighborhoodContext
  alias Storyarn.Flows.AI.SourceLocks
  alias Storyarn.Flows.ContextQueries, as: Context

  defdelegate get_context_node(project_id, node_id), to: Context, as: :get_node

  defdelegate list_context_flows(project_id, flow_ids, limit),
    to: Context,
    as: :list_flow_briefs

  defdelegate get_context_neighborhood(project_id, node_id, max_depth, max_fan_out, max_entities),
    to: Context,
    as: :neighborhood

  defdelegate dialogue_subject(workspace_id, project_id, node_id, opts \\ []),
    to: ContextContract,
    as: :dialogue

  defdelegate flow_neighborhood_subject(workspace_id, project_id, node_id),
    to: ContextContract,
    as: :flow_neighborhood

  defdelegate build_dialogue_context(project, subject_ref, policy, entity_builder),
    to: DialogueContext,
    as: :build

  defdelegate build_flow_neighborhood_context(project, subject_ref, policy, entity_builder),
    to: FlowNeighborhoodContext,
    as: :build

  defdelegate acquire_source_locks(task), to: SourceLocks, as: :acquire
end
