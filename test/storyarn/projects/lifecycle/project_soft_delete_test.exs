defmodule Storyarn.Projects.SoftDeleteTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  describe "soft delete" do
    test "delete_project/2 sets deleted_at and deleted_by_id" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, deleted} = Projects.delete_project(user_scope_fixture(user), project.id)
      assert deleted.deleted_at
      assert deleted.deleted_by_id == user.id
    end

    test "soft-deleted projects are filtered from list_projects/1" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)

      assert Projects.list_projects(scope) == []
    end

    test "soft-deleted projects are filtered from get_project/2" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)

      assert {:error, :not_found} = Projects.get_project(scope, project.id)
    end

    test "soft-deleted projects are filtered from list_projects_for_workspace/2" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)

      assert Projects.list_projects_for_workspace(workspace.id, scope) == []
    end
  end

  describe "list_deleted_projects/1" do
    test "returns soft-deleted projects in workspace" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)

      deleted = Projects.list_deleted_projects(workspace.id)
      assert length(deleted) == 1
      assert hd(deleted).id == project.id
      assert hd(deleted).deleted_at
    end

    test "does not include non-deleted projects" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      _project = project_fixture(user, %{workspace: workspace})

      assert Projects.list_deleted_projects(workspace.id) == []
    end

    test "preloads deleted_by user" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)

      [deleted] = Projects.list_deleted_projects(workspace.id)
      assert deleted.deleted_by.id == user.id
    end
  end

  describe "get_deleted_project/2" do
    test "returns a deleted project" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)

      deleted = Projects.get_deleted_project(workspace.id, project.id)
      assert deleted
      assert deleted.id == project.id
    end

    test "returns nil for non-deleted project" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      assert Projects.get_deleted_project(workspace.id, project.id) == nil
    end
  end

  describe "list_deleted_items_for_retention/1" do
    test "includes generation-fenced asset trash metadata and its purge deadline" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user, %{filename: "discarded.png", size: 2_048})

      assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)
      assert [item] = Projects.list_deleted_items_for_retention()

      assert item.type == "asset"
      assert item.name == "discarded.png"
      assert item.deleted_by_id == user.id
      assert item.deletion_generation == trashed.deletion_generation
      assert item.size == 2_048
      assert item.content_type == "image/jpeg"
      assert item.purge_at == DateTime.add(item.deleted_at, 24 * 60 * 60, :second)
    end

    test "loads retention plans once across workspaces and defaults missing subscriptions" do
      first_user = user_fixture()
      first_project = project_fixture(first_user)
      first_sheet = sheet_fixture(first_project)

      second_user = user_fixture()
      second_project = project_fixture(second_user)
      second_sheet = sheet_fixture(second_project)

      Repo.delete_all(
        from(subscription in Subscription,
          where: subscription.workspace_id == ^second_project.workspace_id
        )
      )

      assert {:ok, _deleted} = Sheets.delete_sheet(first_sheet)
      assert {:ok, _deleted} = Sheets.delete_sheet(second_sheet)

      {items, queries} = capture_queries(&Projects.list_deleted_items_for_retention/0)

      assert MapSet.new(Enum.map(items, & &1.project_id)) ==
               MapSet.new([first_project.id, second_project.id])

      assert Enum.all?(items, fn item ->
               item.purge_at == DateTime.add(item.deleted_at, 24 * 60 * 60, :second)
             end)

      assert length(subscription_queries(queries)) == 1
    end

    test "skips plan lookup when every project has a valid retention override" do
      project =
        project_fixture(nil, %{
          settings: %{"trash_retention_hours" => 720}
        })

      sheet = sheet_fixture(project)
      assert {:ok, _deleted} = Sheets.delete_sheet(sheet)

      {[item], queries} = capture_queries(&Projects.list_deleted_items_for_retention/0)

      assert item.purge_at == DateTime.add(item.deleted_at, 720 * 60 * 60, :second)
      assert subscription_queries(queries) == []
    end

    test "uses a stable cursor to page through deleted items" do
      project = project_fixture()
      first_sheet = sheet_fixture(project)
      second_sheet = sheet_fixture(project)

      assert {:ok, _deleted} = Sheets.delete_sheet(first_sheet)
      assert {:ok, _deleted} = Sheets.delete_sheet(second_sheet)

      assert [first_page_item] = Projects.list_deleted_items_for_retention(limit: 1)

      cursor = {first_page_item.deleted_at, first_page_item.type, first_page_item.id}

      assert [second_page_item] =
               Projects.list_deleted_items_for_retention(limit: 1, after: cursor)

      refute second_page_item.id == first_page_item.id

      final_cursor =
        {second_page_item.deleted_at, second_page_item.type, second_page_item.id}

      assert Projects.list_deleted_items_for_retention(limit: 1, after: final_cursor) == []
    end

    test "normalizes invalid limits and caps oversized batches" do
      project = project_fixture()
      sheet = sheet_fixture(project)
      assert {:ok, _deleted} = Sheets.delete_sheet(sheet)

      assert length(Projects.list_deleted_items_for_retention(limit: nil)) == 1
      assert length(Projects.list_deleted_items_for_retention(limit: -10)) == 1
      assert length(Projects.list_deleted_items_for_retention(limit: 10_000)) == 1
    end

    test "keeps a cleanup run bounded to its starting cutoff" do
      project = project_fixture()
      first_sheet = sheet_fixture(project)
      second_sheet = sheet_fixture(project)

      assert {:ok, _deleted} = Sheets.delete_sheet(first_sheet)
      cutoff = Projects.deleted_items_retention_cutoff()
      assert {:ok, _deleted} = Sheets.delete_sheet(second_sheet)

      assert [item] = Projects.list_deleted_items_for_retention(through: cutoff)
      assert item.id == first_sheet.id
    end

    test "excludes trash that belongs to a deleted project" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert {:ok, _deleted_sheet} = Sheets.delete_sheet(sheet)
      assert [_item] = Projects.list_deleted_items_for_retention()

      assert {:ok, _deleted_project} = Projects.delete_project(user_scope_fixture(user), project.id)
      assert Projects.list_deleted_items_for_retention() == []
      assert Projects.deleted_items_retention_cutoff() == nil
    end

    test "rejects a stale retention candidate after restore and re-delete" do
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

      assert [stale_candidate] = Projects.list_deleted_items_for_retention()
      assert {:ok, restored_sheet} = Sheets.restore_sheet(Repo.get!(Sheet, sheet.id))
      assert {:ok, _deleted_again} = Sheets.delete_sheet(restored_sheet)
      refute Repo.get!(Sheet, sheet.id).deleted_at == stale_candidate.deleted_at

      assert {:error, :retention_candidate_changed} =
               Projects.delete_retention_candidate(
                 stale_candidate,
                 &Sheets.permanently_delete_sheet/1
               )

      assert %Sheet{deleted_at: %DateTime{}} = Repo.get(Sheet, sheet.id)
    end

    test "rejects a retention candidate after its project policy changes" do
      project = project_fixture()
      sheet = sheet_fixture(project)
      assert {:ok, _deleted_sheet} = Sheets.delete_sheet(sheet)
      assert [stale_candidate] = Projects.list_deleted_items_for_retention()

      project
      |> Ecto.Changeset.change(settings: %{"trash_retention_hours" => 720})
      |> Repo.update!()

      assert {:error, :retention_candidate_changed} =
               Projects.delete_retention_candidate(
                 stale_candidate,
                 &Sheets.permanently_delete_sheet/1
               )

      assert %Sheet{deleted_at: %DateTime{}} = Repo.get(Sheet, sheet.id)
    end
  end

  describe "permanently_delete_project/1" do
    test "removes the project from the database" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(user_scope_fixture(user), project.id)
      deleted = Repo.get(Projects.Project, project.id)

      assert {:ok, _} = Projects.permanently_delete_project(deleted)
      assert Repo.get(Projects.Project, project.id) == nil
    end

    test "cascades a project with recorded voice-overs without violating the asset constraint" do
      user = user_fixture()
      project = project_fixture(user)
      audio = audio_asset_fixture(project, user)
      text = localized_text_fixture(project.id)

      assert {:ok, _recorded} =
               Localization.update_text(text, %{
                 vo_asset_id: audio.id,
                 vo_status: "recorded"
               })

      assert {:ok, deleted} = Projects.delete_project(user_scope_fixture(user), project.id)
      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      refute Repo.get(Projects.Project, project.id)
    end

    test "hands off active and trashed asset keys before cascading the project" do
      user = user_fixture()
      project = project_fixture(user)

      active =
        image_asset_fixture(project, user, %{
          blob_hash: String.duplicate("a", 64),
          metadata: %{"thumbnail_key" => Assets.thumbnail_key(Assets.generate_key(project, "active.png"))}
        })

      trashed = image_asset_fixture(project, user)
      assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, trashed.id, user.id)
      assert {:ok, deleted} = Projects.delete_project(user_scope_fixture(user), project.id)

      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      assert Repo.aggregate(from(asset in Asset, where: asset.project_id == ^project.id), :count) == 0
      assert [request] = Repo.all(StorageCleanupRequest)

      assert MapSet.new(request.storage_keys) ==
               MapSet.new([
                 active.key,
                 Assets.thumbnail_key(active.key),
                 BlobStore.blob_key(project.id, active.blob_hash, "png"),
                 trashed.key
               ])
    end

    test "rolls back project deletion when an asset key cannot be handed off exactly" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)

      Repo.update_all(
        from(stored_asset in Asset, where: stored_asset.id == ^asset.id),
        set: [
          key: "projects/#{project.id}/assets/not-a-uuid/asset.png",
          blob_hash: String.duplicate("c", 64)
        ]
      )

      assert {:ok, deleted} = Projects.delete_project(user_scope_fixture(user), project.id)

      assert {:error, :asset_cleanup_not_authorized} =
               Projects.permanently_delete_project(deleted)

      assert Repo.get!(Projects.Project, project.id)
      assert Repo.get!(Asset, asset.id)
      assert Repo.all(StorageCleanupRequest) == []
    end
  end

  defp capture_queries(fun) when is_function(fun, 0) do
    handler_id = "project-trash-plan-query-budget-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid, do: send(pid, {ref, query})
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp subscription_queries(queries) do
    Enum.filter(queries, &String.contains?(&1, ~s(FROM "subscriptions")))
  end
end
