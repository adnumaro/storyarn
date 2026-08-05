defmodule Mix.Tasks.Storyarn.Snapshots.Reset do
  @shortdoc "Previews or executes an exact pre-canonical snapshot reset"
  @moduledoc """
  Produces an audited, retryable reset plan for one exact environment and
  workspace. The default is a read-only dry run.

      mix storyarn.snapshots.reset --environment production --workspace-id 42 \\
        --plan /secure/audit/snapshots-workspace-42.json

      STORYARN_SNAPSHOT_RESET_AUTHORIZATION=... \\
        mix storyarn.snapshots.reset --environment production --workspace-id 42 \\
        --plan /secure/audit/snapshots-workspace-42.json --execute \\
        --confirm-inventory 64_HEX_DIGEST

  Pause snapshot/versioning queues and block writes for the workspace before
  preparing the plan. Never execute a plan after its scope has changed.
  """

  use Mix.Task

  alias Storyarn.Versioning

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
        write_new_plan!(plan_path, plan)
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

    checkpoint = fn updated ->
      try do
        write_plan!(plan_path, updated)
        :ok
      rescue
        _exception -> {:error, :plan_write_failed}
      end
    end

    case Versioning.execute_project_snapshot_reset(plan, confirmation_digest, checkpoint: checkpoint) do
      {:ok, completed} ->
        print_plan(plan_path, completed, "COMPLETED")

      {:error, reason, failed} ->
        write_plan!(plan_path, failed)
        Mix.raise("Snapshot reset stopped safely: #{inspect(reason)}. Retry with the same plan.")
    end
  end

  defp read_plan!(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, plan} <- Jason.decode(bytes),
         :ok <- Versioning.validate_project_snapshot_reset_plan(plan) do
      plan
    else
      {:error, reason} -> Mix.raise("Could not read a valid reset plan: #{inspect(reason)}")
    end
  end

  defp write_plan!(path, plan) do
    temporary = write_temporary_plan!(path, plan)

    try do
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end

  defp write_new_plan!(path, plan) do
    temporary = write_temporary_plan!(path, plan)

    try do
      case :file.make_link(String.to_charlist(temporary), String.to_charlist(Path.expand(path))) do
        :ok -> :ok
        {:error, :eexist} -> Mix.raise("Refusing to overwrite an existing snapshot reset plan: #{Path.expand(path)}")
        {:error, reason} -> Mix.raise("Could not persist the snapshot reset plan: #{inspect(reason)}")
      end
    after
      File.rm(temporary)
    end
  end

  defp write_temporary_plan!(path, plan) do
    directory = Path.dirname(Path.expand(path))
    temporary = Path.join(directory, ".#{Path.basename(path)}.#{System.unique_integer([:positive])}.tmp")
    File.mkdir_p!(directory)
    File.write!(temporary, Jason.encode_to_iodata!(plan, pretty: true), [:binary, :sync])
    File.chmod!(temporary, 0o600)
    temporary
  end

  defp print_plan(path, plan, label) do
    Mix.shell().info("Snapshot reset #{label}")
    Mix.shell().info("Environment: #{plan["environment"]}")
    Mix.shell().info("Workspace: #{plan["workspace_id"]}")
    Mix.shell().info("Snapshot rows: #{length(plan["snapshot_row_ids"])}")
    Mix.shell().info("Entity-version rows: #{length(plan["entity_version_row_ids"])}")
    Mix.shell().info("Storage objects: #{length(plan["objects"])}")
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
