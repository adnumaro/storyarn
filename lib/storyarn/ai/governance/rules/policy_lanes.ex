defmodule Storyarn.AI.Governance.Rules.PolicyLanes do
  @moduledoc "Pure normalization and role-specific interpretation of workspace AI lanes."

  alias Storyarn.AI.WorkspacePolicy

  @spec normalize([String.t()]) :: {:ok, [String.t()]} | {:error, :invalid_policy}
  def normalize(lanes) when is_list(lanes) do
    normalized = lanes |> Enum.uniq() |> Enum.sort()

    if Enum.all?(normalized, &(&1 in WorkspacePolicy.initial_lanes())),
      do: {:ok, normalized},
      else: {:error, :invalid_policy}
  end

  def normalize(_lanes), do: {:error, :invalid_policy}

  @spec effective(WorkspacePolicy.t() | [String.t()], String.t() | nil) :: [String.t()]
  def effective(%WorkspacePolicy{allowed_lanes: lanes}, workspace_role), do: effective(lanes, workspace_role)
  def effective(lanes, "owner") when is_list(lanes), do: Enum.uniq(["personal_byok" | lanes])
  def effective(lanes, _workspace_role) when is_list(lanes), do: lanes

  @spec personal_allowed?(WorkspacePolicy.t() | [String.t()], String.t() | nil) :: boolean()
  def personal_allowed?(_policy_or_lanes, nil), do: false
  def personal_allowed?(_policy_or_lanes, "owner"), do: true

  def personal_allowed?(%WorkspacePolicy{allowed_lanes: lanes}, workspace_role),
    do: personal_allowed?(lanes, workspace_role)

  def personal_allowed?(lanes, _workspace_role) when is_list(lanes), do: "personal_byok" in lanes
end
