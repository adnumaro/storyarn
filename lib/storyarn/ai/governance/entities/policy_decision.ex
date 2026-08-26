defmodule Storyarn.AI.PolicyDecision do
  @moduledoc "Immutable actor authorization decision, separate from its evaluation workflow."

  @enforce_keys [
    :actor_id,
    :workspace_id,
    :project_id,
    :task_id,
    :phase,
    :policy_version,
    :allowed_lanes,
    :base_permission,
    :domain_permission
  ]
  defstruct [
    :actor_id,
    :workspace_id,
    :project_id,
    :task_id,
    :phase,
    :policy_version,
    :allowed_lanes,
    :base_permission,
    :domain_permission,
    :project_role,
    :workspace_role,
    bulk?: false,
    scheduled?: false
  ]

  @type t :: %__MODULE__{}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = decision) do
    %{
      "workspace_id" => decision.workspace_id,
      "actor_id" => decision.actor_id,
      "project_id" => decision.project_id,
      "task_id" => decision.task_id,
      "phase" => Atom.to_string(decision.phase),
      "policy_version" => decision.policy_version,
      "allowed_lanes" => Enum.map(decision.allowed_lanes, &Atom.to_string/1),
      "base_permission" => Atom.to_string(decision.base_permission),
      "domain_permission" => Atom.to_string(decision.domain_permission),
      "project_role" => decision.project_role,
      "workspace_role" => decision.workspace_role,
      "bulk" => decision.bulk?,
      "scheduled" => decision.scheduled?
    }
  end
end
