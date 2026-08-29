defmodule Storyarn.Architecture.InvitationDeliveryBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy
  alias Storyarn.Workers.DeliverProjectInvitationWorker
  alias Storyarn.Workers.DeliverWorkspaceInvitationWorker

  @legacy_worker_path "lib/storyarn/workers/platform/deliver_invitation_worker.ex"
  @platform_delivery_root "lib/storyarn/platform/delivery"

  test "invitation delivery is owned by the producing contexts" do
    refute File.exists?(@legacy_worker_path)
    refute File.exists?(@platform_delivery_root)

    oban_queues = :storyarn |> Application.fetch_env!(Oban) |> Keyword.fetch!(:queues)

    assert Keyword.fetch!(oban_queues, :invitation_delivery) == 10
    assert DeliverProjectInvitationWorker.__opts__()[:queue] == :invitation_delivery
    assert DeliverProjectInvitationWorker.__opts__()[:max_attempts] == 5
    assert DeliverWorkspaceInvitationWorker.__opts__()[:queue] == :invitation_delivery
    assert DeliverWorkspaceInvitationWorker.__opts__()[:max_attempts] == 5
  end

  test "compiled owner workers enter only their own bounded-context facade" do
    project_imports = imported_storyarn_modules(DeliverProjectInvitationWorker)
    workspace_imports = imported_storyarn_modules(DeliverWorkspaceInvitationWorker)

    assert Storyarn.Projects in project_imports
    refute Enum.any?(project_imports, &foreign_context?(&1, Storyarn.Projects))

    assert Storyarn.Workspaces in workspace_imports
    refute Enum.any?(workspace_imports, &foreign_context?(&1, Storyarn.Workspaces))
  end

  test "the ratchet rejects owner workers crossing contexts and leaves the retired Platform slice unclassified" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    graph = %{
      "lib/storyarn/workers/platform/future_invitation_worker.ex" => %{
        "lib/storyarn/projects.ex" => "runtime",
        "lib/storyarn/workspaces.ex" => "runtime"
      },
      "lib/storyarn/workers/projects/future_invitation_worker.ex" => %{
        "lib/storyarn/workspaces.ex" => "runtime"
      },
      "lib/storyarn/workers/workspaces/future_invitation_worker.ex" => %{
        "lib/storyarn/projects.ex" => "runtime"
      }
    }

    assert DependencyPolicy.unclassified_paths(graph, policy) == [
             "lib/storyarn/workers/platform/future_invitation_worker.ex"
           ]

    forbidden = DependencyPolicy.forbidden_edges(graph, policy)

    assert MapSet.size(forbidden.platform) == 0
    assert MapSet.size(forbidden.projects) == 1
    assert MapSet.size(forbidden.workspaces) == 1
  end

  test "no reviewed contract can hide the retired Platform callback path" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")
    reviewed_edges = policy.durable_contracts ++ policy.migration_exceptions

    refute Enum.any?(policy.additional_durable_contract_targets, fn contract ->
             String.starts_with?(contract.target, "lib/storyarn/platform/delivery/")
           end)

    refute Enum.any?(reviewed_edges, fn edge ->
             edge.source == @legacy_worker_path or
               String.starts_with?(edge.target, "lib/storyarn/platform/delivery/")
           end)
  end

  defp imported_storyarn_modules(module) do
    module
    |> :code.which()
    |> :beam_lib.chunks([:imports])
    |> case do
      {:ok, {_module, [imports: imports]}} ->
        imports
        |> Enum.map(&elem(&1, 0))
        |> Enum.filter(&(&1 |> Atom.to_string() |> String.starts_with?("Elixir.Storyarn.")))
        |> MapSet.new()

      {:error, reason} ->
        flunk("cannot inspect compiled imports for #{inspect(module)}: #{inspect(reason)}")
    end
  end

  defp foreign_context?(module, owner_facade) do
    module_name = Atom.to_string(module)
    owner_name = Atom.to_string(owner_facade)

    Enum.any?(~w(Accounts AI Flows Localization Projects Scenes Sheets Workspaces), fn context ->
      prefix = "Elixir.Storyarn.#{context}"
      String.starts_with?(module_name, prefix) and module_name != owner_name
    end)
  end
end
