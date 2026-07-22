defmodule Storyarn.AI.RouteResolver do
  @moduledoc """
  Minimal Slice-2 route resolver.

  It exposes only operator-configured routes. Slice 5 replaces the single
  managed assignment with central routing and personal preferences.
  """

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Task

  @spec routes(PolicyDecision.t(), Task.t()) :: [ExecutionRoute.t()]
  def routes(%PolicyDecision{} = decision, %Task{} = task) do
    Enum.flat_map(decision.allowed_lanes, &route_for_lane(&1, decision, task))
  end

  @spec current?(PolicyDecision.t(), Task.t(), ExecutionRoute.t()) :: boolean()
  def current?(%PolicyDecision{} = decision, %Task{} = task, %ExecutionRoute{} = route) do
    Enum.any?(routes(decision, task), &(&1 == route))
  end

  defp route_for_lane(:managed, decision, task) do
    config = config()[:managed]

    with true <- is_list(config),
         true <- Settlement.available?(:managed),
         provider when is_binary(provider) <- config[:provider],
         model when is_binary(model) <- config[:model],
         reference when is_binary(reference) <- config[:credential_ref],
         {:ok, credential_ref} <- CredentialRef.new(:managed, reference),
         %{id: price_id, version: price_version} <- task.managed_price do
      [
        %ExecutionRoute{
          lane: :managed,
          provider: provider,
          model: model,
          credential_ref: credential_ref,
          payer: config[:payer] || "storyarn",
          assignment_source: config[:assignment_source] || "operator_default",
          consent_basis: config[:consent_basis] || "workspace_policy",
          policy_version: decision.policy_version,
          price_id: price_id,
          price_version: price_version
        }
      ]
    else
      _unavailable -> []
    end
  end

  # Slice 4 adds the personal route through this same resolver contract.
  defp route_for_lane(_lane, _decision, _task), do: []

  defp config do
    Application.get_env(:storyarn, __MODULE__, [])
  end
end
