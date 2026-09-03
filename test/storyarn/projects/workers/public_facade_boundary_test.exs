defmodule Storyarn.Projects.Workers.PublicFacadeBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workers.InspectStorageMultipartInventoryWorker

  @active_states [:available, :scheduled, :executing, :retryable]
  @worker_contract [
    {Storyarn.Workers.BuildProjectSnapshotWorker, :snapshot_archives, 3, nil, [:worker, :args], :infinity},
    {Storyarn.Workers.CleanupProjectSnapshotWorker, :storage_cleanup, 10, nil, [:worker, :queue, :args], :infinity},
    {Storyarn.Workers.DeleteProjectTemplateArtifactsWorker, :templates, 5, nil, nil, nil},
    {Storyarn.Workers.DeleteStorageObjectsWorker, :storage_cleanup, 5, nil, [:worker, :queue, :args], :infinity},
    {Storyarn.Workers.DeliverProjectInvitationWorker, :invitation_delivery, 5, nil, nil, nil},
    {Storyarn.Workers.ExpireProjectImportsWorker, :imports_maintenance, 3, nil, nil, nil},
    {Storyarn.Workers.ImportProjectSnapshotWorker, :snapshot_imports, 3, nil, [:worker, :args], :infinity},
    {Storyarn.Workers.ImportProjectWorker, :imports, 3, nil, nil, nil},
    {Storyarn.Workers.InspectProjectSnapshotsWorker, :snapshots_maintenance, 5, 3, [:worker, :args], 86_400},
    {InspectStorageMultipartInventoryWorker, :storage_inventory, 3, 3, [:worker, :args], 29 * 60},
    {Storyarn.Workers.InstallProjectTemplateWorker, :template_installs, 3, nil, nil, nil},
    {Storyarn.Workers.ProjectSnapshotRetentionWorker, :snapshots_maintenance, 5, nil, [:worker, :args], 600},
    {Storyarn.Workers.PublishProjectTemplateWorker, :templates, 3, nil, nil, nil},
    {Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker, :snapshots_maintenance, 5, nil, [:worker, :args], 600},
    {Storyarn.Workers.ReconcileProjectSnapshotRepairWorker, :snapshots_maintenance, 5, 3, [:worker, :args], 600},
    {Storyarn.Workers.RepairProjectSnapshotFindingWorker, :snapshots_maintenance, 5, 3, [:worker, :args], :infinity},
    {Storyarn.Workers.RestoreProjectSnapshotWorker, :snapshot_restores, 5, nil, [:worker, :args], :infinity},
    {Storyarn.Workers.RetryStorageCleanupRequestsWorker, :storage_cleanup, 5, nil, :omitted, 600},
    {Storyarn.Workers.TrashRetentionWorker, :default, 3, nil, nil, nil}
  ]

  test "Projects workers orchestrate only through the root context facade" do
    worker_files = Path.wildcard("lib/storyarn/workers/projects/*.ex")

    assert length(worker_files) == length(@worker_contract)

    violations = Enum.flat_map(worker_files, &internal_project_references/1)

    assert violations == [],
           "Projects workers must call Storyarn.Projects instead of an internal module: #{inspect(violations)}"
  end

  test "persisted Project worker identities and Oban options remain exact" do
    expected_modules = MapSet.new(@worker_contract, &elem(&1, 0))
    assert modules_in_worker_files() == expected_modules

    for {worker, queue, max_attempts, priority, unique_fields, unique_period} <- @worker_contract do
      opts = worker.__opts__()

      assert Keyword.fetch!(opts, :queue) == queue, "#{inspect(worker)} queue changed"

      assert Keyword.fetch!(opts, :max_attempts) == max_attempts,
             "#{inspect(worker)} max_attempts changed"

      assert_optional_option(opts, :priority, priority, worker)
      assert_unique_options(opts, unique_fields, unique_period, worker)
    end
  end

  test "the worker ratchet recognizes grouped and root-aliased bypasses" do
    source = """
    alias Storyarn.Projects.{Assets, Versioning}
    alias Storyarn.Projects

    Projects.Versioning.perform_project_snapshot_build(1, [])
    """

    references = project_references_in_source(source, "synthetic_worker.ex")

    assert Enum.any?(references, &String.ends_with?(&1, "Storyarn.Projects.Assets"))
    assert Enum.any?(references, &String.ends_with?(&1, "Storyarn.Projects.Versioning"))
    assert Enum.any?(references, &String.ends_with?(&1, "Projects.Versioning"))
  end

  defp internal_project_references(file_path) do
    file_path
    |> File.read!()
    |> project_references_in_source(file_path)
  end

  defp project_references_in_source(source, file_path) do
    ast = Code.string_to_quoted!(source, file: file_path, columns: true)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:alias, metadata,
         [
           {{:., _, [{:__aliases__, _, [:Storyarn, :Projects]}, :{}]}, _, grouped_aliases}
         ]} = node,
        acc ->
          references =
            Enum.map(grouped_aliases, fn {:__aliases__, _, segments} ->
              project_reference(file_path, metadata, [:Storyarn, :Projects | segments])
            end)

          {node, references ++ acc}

        {:__aliases__, metadata, [:Storyarn, :Projects, _internal | _rest] = segments} = node, acc ->
          {node, [project_reference(file_path, metadata, segments) | acc]}

        {:__aliases__, metadata, [:Projects, _internal | _rest] = segments} = node, acc ->
          {node, [project_reference(file_path, metadata, segments) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(references)
  end

  defp modules_in_worker_files do
    "lib/storyarn/workers/projects/*.ex"
    |> Path.wildcard()
    |> MapSet.new(fn file_path ->
      [module_name] = Regex.run(~r/^defmodule\s+([A-Za-z0-9_.]+)\s+do/m, File.read!(file_path), capture: :all_but_first)
      Module.concat([module_name])
    end)
  end

  defp assert_optional_option(opts, key, nil, worker) do
    refute Keyword.has_key?(opts, key), "#{inspect(worker)} unexpectedly declares #{key}"
  end

  defp assert_optional_option(opts, key, expected, worker) do
    assert Keyword.fetch!(opts, key) == expected, "#{inspect(worker)} #{key} changed"
  end

  defp assert_unique_options(opts, nil, nil, worker) do
    refute Keyword.has_key?(opts, :unique), "#{inspect(worker)} unexpectedly declares uniqueness"
  end

  defp assert_unique_options(opts, expected_fields, expected_period, worker) do
    unique = Keyword.fetch!(opts, :unique)

    assert Keyword.fetch!(unique, :period) == expected_period,
           "#{inspect(worker)} unique period changed"

    assert Keyword.fetch!(unique, :states) == @active_states,
           "#{inspect(worker)} unique states changed"

    case expected_fields do
      :omitted ->
        refute Keyword.has_key?(unique, :fields),
               "#{inspect(worker)} unexpectedly declares unique fields"

      fields ->
        assert Keyword.fetch!(unique, :fields) == fields,
               "#{inspect(worker)} unique fields changed"
    end
  end

  defp project_reference(file_path, metadata, segments) do
    "#{file_path}:#{metadata[:line]}: #{Enum.join(segments, ".")}"
  end
end
