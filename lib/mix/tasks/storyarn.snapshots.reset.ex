defmodule Mix.Tasks.Storyarn.Snapshots.Reset do
  @shortdoc "Previews or executes an exact pre-canonical snapshot reset"
  @moduledoc """
  Produces an audited, retryable reset plan for one exact environment and
  workspace. The default is a read-only dry run.

      mix storyarn.snapshots.reset --environment production --workspace-id 42 \\
        --plan /secure/audit/snapshots-workspace-42.json

      STORYARN_SNAPSHOT_RESET_AUTHORIZATION=... \\
      STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256=... \\
        mix storyarn.snapshots.reset --environment production --workspace-id 42 \\
        --plan /secure/audit/snapshots-workspace-42.json --execute \\
        --confirm-inventory 64_HEX_DIGEST

  Before preparing or executing a plan, establish the global write fence from
  the versioning-containment runbook: stop every application node and queue
  worker, revoke every other storage write credential, wait for IAM propagation,
  and verify those credentials can no longer write. Never execute a plan after
  its scope has changed.
  """

  use Mix.Task

  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshotReset

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          environment: :string,
          workspace_id: :integer,
          plan: :string,
          execute: :boolean,
          confirm_inventory: :string
        ]
      )

    if positional != [], do: Mix.raise("Unexpected positional arguments: #{Enum.join(positional, " ")}")

    environment = required!(opts, :environment)
    workspace_id = required!(opts, :workspace_id)
    plan_path = required!(opts, :plan)

    if Keyword.get(opts, :execute, false) do
      execute!(plan_path, environment, workspace_id, required!(opts, :confirm_inventory))
    else
      prepare!(plan_path, environment, workspace_id)
    end
  end

  defp prepare!(plan_path, environment, workspace_id) do
    case Versioning.prepare_project_snapshot_reset(workspace_id, environment) do
      {:ok, plan} ->
        persist_new_plan!(plan_path, plan)
        print_plan(plan_path, plan, "DRY RUN")

      {:error, reason} ->
        Mix.raise("Could not prepare snapshot reset: #{inspect(reason)}")
    end
  end

  defp execute!(plan_path, environment, workspace_id, confirmation_digest) do
    plan = read_plan!(plan_path)

    if plan["environment"] != environment or plan["workspace_id"] != workspace_id do
      Mix.raise("The plan does not match the explicit environment and workspace scope.")
    end

    checkpoint = &ProjectSnapshotReset.write_plan_file(plan_path, &1)

    case Versioning.execute_project_snapshot_reset(plan, confirmation_digest,
           authorization: System.get_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION"),
           checkpoint: checkpoint
         ) do
      {:ok, completed} ->
        print_plan(plan_path, completed, "COMPLETED")

      {:error, reason, failed} ->
        persist_plan!(plan_path, failed)
        Mix.raise("Snapshot reset stopped safely: #{inspect(reason)}. Retry with the same plan.")
    end
  end

  defp read_plan!(path) do
    case ProjectSnapshotReset.read_plan_file(path) do
      {:ok, plan} -> plan
      {:error, reason} -> Mix.raise("Could not read a valid reset plan: #{inspect(reason)}")
    end
  end

  defp persist_plan!(path, plan) do
    case ProjectSnapshotReset.write_plan_file(path, plan) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Could not checkpoint the snapshot reset plan: #{inspect(reason)}")
    end
  end

  defp persist_new_plan!(path, plan) do
    case ProjectSnapshotReset.write_new_plan_file(path, plan) do
      :ok ->
        :ok

      {:error, :snapshot_reset_plan_exists} ->
        Mix.raise("Refusing to overwrite an existing snapshot reset plan: #{Path.expand(path)}")

      {:error, reason} ->
        Mix.raise("Could not persist the snapshot reset plan: #{inspect(reason)}")
    end
  end

  defp print_plan(path, plan, label) do
    Mix.shell().info("Snapshot reset #{label}")
    Mix.shell().info("Environment: #{plan["environment"]}")
    Mix.shell().info("Workspace: #{plan["workspace_id"]}")
    Mix.shell().info("Snapshot rows: #{length(plan["snapshot_row_ids"])}")
    Mix.shell().info("Entity-version rows: #{length(plan["entity_version_row_ids"])}")
    Mix.shell().info("Storage objects: #{length(plan["objects"])}")
    Mix.shell().info("Storage bytes: #{Enum.sum(Enum.map(plan["objects"], & &1["size"]))}")
    Mix.shell().info("Remaining objects: #{length(plan["remaining_storage_keys"])}")
    Mix.shell().info("Inventory digest: #{plan["inventory_digest"]}")
    Mix.shell().info("Audit plan: #{Path.expand(path)}")
  end

  defp required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> Mix.raise("Missing required option --#{key |> Atom.to_string() |> String.replace("_", "-")}")
    end
  end
end
