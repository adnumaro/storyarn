defmodule Mix.Tasks.Storyarn.Ai.Diagnose do
  @shortdoc "Runs the operator-only managed AI production diagnostic"
  @moduledoc """
  Exercises the complete managed execution kernel with content-free input.
  The selected actor must own the workspace, be invited through the AI feature
  flag, have managed policy enabled, and the workspace must have allowance.

      mix storyarn.ai.diagnose --workspace-id 123 --actor-id 456
  """

  use Mix.Task

  alias Storyarn.Accounts
  alias Storyarn.AI
  alias Storyarn.AI.Tasks.ManagedDiagnostic
  alias Storyarn.Repo

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args, strict: [workspace_id: :integer, actor_id: :integer])

    if positional != [], do: usage!()

    workspace_id = required!(opts, :workspace_id)
    actor_id = required!(opts, :actor_id)
    user = Repo.get(Storyarn.Accounts.User, actor_id) || Mix.raise("Actor not found")
    scope = Accounts.Scope.for_user(user)
    input = %{"probe" => ManagedDiagnostic.probe()}

    {:ok, intent} =
      AI.new_intent(scope, %{
        workspace_id: workspace_id,
        task_id: "operator.managed_diagnostic",
        input: input
      })

    with {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} <- AI.preflight(intent),
         execute_intent = %{
           intent
           | requested_route_ref: route_ref,
             idempotency_key: "diagnostic-#{System.unique_integer([:positive, :monotonic])}"
         },
         {:ok, operation} <- AI.execute(execute_intent),
         {:ok, %{"status" => "ok"}, _operation} <- AI.get_result(scope, operation.id) do
      Mix.shell().info("Managed AI diagnostic succeeded as operation ##{operation.id}")
    else
      {:ok, %{route_options: routes}} -> Mix.raise("Expected exactly one managed route, got: #{inspect(routes)}")
      {:error, reason} -> Mix.raise("Managed AI diagnostic failed: #{inspect(reason)}")
      unexpected -> Mix.raise("Managed AI diagnostic returned: #{inspect(unexpected)}")
    end
  end

  defp required!(opts, key), do: Keyword.get(opts, key) || usage!()

  defp usage! do
    Mix.raise("Usage: mix storyarn.ai.diagnose --workspace-id ID --actor-id ID")
  end
end
