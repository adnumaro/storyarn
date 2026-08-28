defmodule Mix.Tasks.Storyarn.SnapshotArchiveSmoke do
  @shortdoc "Verifies a persisted snapshot archive through a real signed provider GET"
  @moduledoc """
  Local wrapper for the read-only snapshot archive provider smoke.

  It starts only the runtime dependencies required by the repository and HTTP
  clients, then starts `Storyarn.Repo` directly if the application is not
  already running. It never starts `Storyarn.Application` or Oban.

      mix storyarn.snapshot_archive_smoke --snapshot-id 123 --yes-read-only

  Production releases must invoke `Storyarn.Projects.run_snapshot_archive_smoke!/1`
  through the release `rpc` command instead of running Mix.
  """

  use Mix.Task

  alias Storyarn.Projects
  alias Storyarn.Repo

  @runtime_applications [:ecto_sql, :postgrex, :req, :ex_aws, :ex_aws_s3]
  @usage "Usage: mix storyarn.snapshot_archive_smoke --snapshot-id ID --yes-read-only"

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [snapshot_id: :integer, yes_read_only: :boolean]
      )

    if positional != [], do: usage!()
    if Keyword.get(opts, :yes_read_only) != true, do: usage!()

    snapshot_id = required_positive_integer!(opts, :snapshot_id)
    ensure_runtime_started!()

    result = Projects.run_snapshot_archive_smoke!(snapshot_id)

    Mix.shell().info(
      "Snapshot archive provider smoke succeeded " <>
        "(#{result.size_bytes} bytes; multipart inventory, full GET, SHA-256, headers, and Range verified)."
    )
  rescue
    exception in [ArgumentError, RuntimeError] -> Mix.raise(Exception.message(exception))
  end

  @doc false
  @spec runtime_applications() :: [atom()]
  def runtime_applications, do: @runtime_applications

  defp ensure_runtime_started! do
    Enum.each(@runtime_applications, &ensure_application_started!/1)
    ensure_repo_started!()
  end

  defp ensure_application_started!(application) do
    case Application.ensure_all_started(application) do
      {:ok, _started} -> :ok
      {:error, reason} -> Mix.raise("Could not start #{application}: #{inspect(reason)}")
    end
  end

  defp ensure_repo_started! do
    case Process.whereis(Repo) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case Repo.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> Mix.raise("Could not start Storyarn.Repo: #{inspect(reason)}")
        end
    end
  end

  defp required_positive_integer!(opts, key) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> usage!()
    end
  end

  defp usage!, do: Mix.raise(@usage)
end
