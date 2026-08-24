defmodule Storyarn.Workers.TrashRetentionWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Platform.Billing
  alias Storyarn.Projects
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

  test "purges an expired asset through the generation-fenced asset trash API" do
    %{asset: asset, project: project} = expired_trashed_asset_context()
    Application.put_env(:storyarn, TrashRetentionWorker, enabled: true)

    assert Billing.project_storage_usage(project.id).asset_trash == %{bytes: asset.size, count: 1}
    assert :ok = perform_job(TrashRetentionWorker, %{})
    refute Repo.get(Asset, asset.id)
    assert Billing.project_storage_usage(project.id).asset_trash == %{bytes: 0, count: 0}
  end

  test "purges an expired original and variant family without warning on the stale sibling candidate" do
    user = user_fixture()
    project = project_fixture(user)
    original = image_asset_fixture(project, user, %{filename: "retention-original.png"})
    variant = image_asset_fixture(project, user, %{filename: "retention-variant.webp"})

    assert {:ok, original} =
             Assets.update_asset(original, %{
               metadata: %{"web_asset_id" => variant.id, "web_url" => variant.url}
             })

    assert {:ok, _variant} =
             Assets.update_asset(variant, %{
               metadata: %{"is_variant" => true, "original_asset_id" => original.id}
             })

    assert {:ok, _trashed_original} =
             Assets.move_asset_to_trash(project.id, original.id, user.id)

    expired_at =
      DateTime.utc_now()
      |> DateTime.add(-48 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(stored_asset in Asset, where: stored_asset.id in ^[original.id, variant.id]),
      set: [deleted_at: expired_at]
    )

    family_candidates =
      Enum.filter(
        Projects.list_deleted_items_for_retention(),
        &(&1.type == "asset" and &1.project_id == project.id)
      )

    assert Enum.map(family_candidates, & &1.id) == [original.id, variant.id]
    stale_variant_candidate = Enum.at(family_candidates, 1)

    Application.put_env(:storyarn, TrashRetentionWorker, enabled: true)

    log =
      capture_log(fn ->
        assert :ok = perform_job(TrashRetentionWorker, %{})
      end)

    refute Repo.get(Asset, original.id)
    refute Repo.get(Asset, variant.id)
    refute log =~ "Failed to permanently delete asset"
    refute log =~ "Trash retention failed for asset"

    assert {:error, :asset_not_found} =
             Projects.purge_asset_trash_candidate(stale_variant_candidate, nil)
  end

  test "a stale asset retention candidate cannot purge a later trash generation" do
    %{asset: asset, project: project, user: user} = expired_trashed_asset_context()
    [candidate] = Projects.list_deleted_items_for_retention()

    assert candidate.type == "asset"
    assert candidate.deletion_generation == asset.deletion_generation

    assert {:ok, restored} =
             Assets.restore_trashed_asset(project.id, asset.id, asset.deletion_generation, user.id)

    assert {:ok, retrash} = Assets.move_asset_to_trash(project.id, restored.id, user.id)
    assert retrash.deletion_generation > candidate.deletion_generation

    assert {:error, :asset_trash_generation_changed} =
             Projects.purge_asset_trash_candidate(candidate, nil)

    assert %Asset{deleted_at: %DateTime{}} = Repo.get(Asset, asset.id)
  end

  test "an asset retention candidate cannot outlive a project policy change" do
    %{asset: asset, project: project} = expired_trashed_asset_context()
    [candidate] = Projects.list_deleted_items_for_retention()

    project
    |> Ecto.Changeset.change(settings: %{"trash_retention_hours" => 72})
    |> Repo.update!()

    assert {:error, :asset_trash_retention_changed} =
             Projects.purge_asset_trash_candidate(candidate, nil)

    assert %Asset{deleted_at: %DateTime{}} = Repo.get(Asset, asset.id)
  end

  test "keeps asset trash until the current project retention policy expires" do
    %{asset: asset, project: project} = expired_trashed_asset_context()

    project
    |> Ecto.Changeset.change(settings: %{"trash_retention_hours" => 72})
    |> Repo.update!()

    Application.put_env(:storyarn, TrashRetentionWorker, enabled: true)

    assert :ok = perform_job(TrashRetentionWorker, %{})
    assert %Asset{deleted_at: %DateTime{}} = Repo.get(Asset, asset.id)
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

  defp expired_trashed_asset_context do
    user = user_fixture()
    project = project_fixture(user)
    asset = asset_fixture(project, user)
    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    expired_at =
      DateTime.utc_now()
      |> DateTime.add(-48 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(stored_asset in Asset, where: stored_asset.id == ^asset.id),
      set: [deleted_at: expired_at]
    )

    %{asset: Repo.get!(Asset, trashed.id), project: project, user: user}
  end
end
