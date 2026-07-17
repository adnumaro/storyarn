defmodule Storyarn.Workers.TrashRetentionWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Workers.TrashRetentionWorker

  setup do
    original_config = Application.get_env(:storyarn, TrashRetentionWorker)
    Application.put_env(:storyarn, TrashRetentionWorker, enabled: false)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, TrashRetentionWorker)
      else
        Application.put_env(:storyarn, TrashRetentionWorker, original_config)
      end
    end)

    :ok
  end

  test "an already queued job cannot purge eligible trash while disabled" do
    sheet = expired_trashed_sheet()

    assert :ok = perform_job(TrashRetentionWorker, %{})
    assert %Sheet{deleted_at: %DateTime{}} = Repo.get(Sheet, sheet.id)
  end

  test "missing and malformed configuration fail closed" do
    sheet = expired_trashed_sheet()

    for invalid_config <- [nil, %{}, [enabled: "true"], [enabled: 1], ["invalid"]] do
      if is_nil(invalid_config) do
        Application.delete_env(:storyarn, TrashRetentionWorker)
      else
        Application.put_env(:storyarn, TrashRetentionWorker, invalid_config)
      end

      assert :ok = perform_job(TrashRetentionWorker, %{})
      assert Repo.get(Sheet, sheet.id)
    end
  end

  test "the fixture is purged only when retention is explicitly enabled" do
    sheet = expired_trashed_sheet()
    Application.put_env(:storyarn, TrashRetentionWorker, enabled: true)

    assert :ok = perform_job(TrashRetentionWorker, %{})
    refute Repo.get(Sheet, sheet.id)
  end

  defp expired_trashed_sheet do
    project = project_fixture()
    sheet = sheet_fixture(project)
    assert {:ok, _deleted_sheet} = Sheets.delete_sheet(sheet)

    expired_at =
      DateTime.utc_now()
      |> DateTime.add(-48 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(stored_sheet in Sheet, where: stored_sheet.id == ^sheet.id),
      set: [deleted_at: expired_at]
    )

    sheet
  end
end
