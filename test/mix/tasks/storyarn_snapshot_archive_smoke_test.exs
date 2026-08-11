defmodule Mix.Tasks.Storyarn.SnapshotArchiveSmokeTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Storyarn.SnapshotArchiveSmoke

  test "requires an explicit read-only acknowledgement before any provider access" do
    assert_raise Mix.Error,
                 "Usage: mix storyarn.snapshot_archive_smoke --snapshot-id ID --yes-read-only",
                 fn ->
                   SnapshotArchiveSmoke.run(["--snapshot-id", "1"])
                 end
  end

  test "fails closed when the real S3-compatible adapter is not configured" do
    original_storage = Application.get_env(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, adapter: :local)

    on_exit(fn -> restore_env(:storyarn, :storage, original_storage) end)

    assert_raise Mix.Error,
                 "The real S3-compatible production storage adapter is not configured.",
                 fn ->
                   SnapshotArchiveSmoke.run(["--snapshot-id", "1", "--yes-read-only"])
                 end
  end

  test "has no app.start requirement and its dependency closure excludes Storyarn and Oban" do
    requirements =
      :attributes
      |> SnapshotArchiveSmoke.__info__()
      |> Keyword.get_values(:requirements)
      |> List.flatten()

    refute "app.start" in requirements

    applications = SnapshotArchiveSmoke.runtime_applications()
    refute :storyarn in applications
    refute :oban in applications

    closure = application_dependency_closure(applications)
    refute :storyarn in closure
    refute :oban in closure
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp application_dependency_closure(applications) do
    visit_applications(applications, MapSet.new())
  end

  defp visit_applications([], visited), do: MapSet.to_list(visited)

  defp visit_applications([application | rest], visited) do
    if MapSet.member?(visited, application) do
      visit_applications(rest, visited)
    else
      dependencies =
        List.wrap(Application.spec(application, :applications)) ++
          List.wrap(Application.spec(application, :included_applications))

      visit_applications(rest ++ dependencies, MapSet.put(visited, application))
    end
  end
end
