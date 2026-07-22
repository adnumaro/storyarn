defmodule Storyarn.Versioning.ProjectSnapshotCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.Sheets.Block
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotStorage

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    flow = flow_fixture(project)
    _node = node_fixture(flow, %{type: "dialogue"})

    %{user: user, project: project, sheet: sheet, flow: flow}
  end

  describe "create_project_snapshot/3" do
    test "creates a snapshot with stored data", %{project: project, user: user} do
      assert {:ok, %ProjectSnapshot{} = snapshot} =
               Versioning.create_project_snapshot(project.id, user.id, title: "v1")

      assert snapshot.project_id == project.id
      assert snapshot.version_number == 1
      assert snapshot.title == "v1"
      assert snapshot.storage_key =~ ~r|snapshots/project/#{snapshot.version_number}-[a-f0-9]{16}\.json\.gz$|
      assert snapshot.snapshot_size_bytes > 0
      assert snapshot.checksum =~ ~r/\A[0-9a-f]{64}\z/
      assert snapshot.created_by_id == user.id
      assert snapshot.entity_counts["sheets"] >= 1
      assert snapshot.entity_counts["flows"] >= 1
    end

    test "increments version numbers", %{project: project, user: user} do
      {:ok, s1} = Versioning.create_project_snapshot(project.id, user.id)
      {:ok, s2} = Versioning.create_project_snapshot(project.id, user.id)

      assert s1.version_number == 1
      assert s2.version_number == 2
    end

    test "creates snapshot without title", %{project: project, user: user} do
      assert {:ok, %ProjectSnapshot{title: nil}} =
               Versioning.create_project_snapshot(project.id, user.id)
    end
  end

  describe "list_project_snapshots/2" do
    test "returns snapshots ordered by version_number desc", %{project: project, user: user} do
      {:ok, _s1} = Versioning.create_project_snapshot(project.id, user.id, title: "First")
      {:ok, _s2} = Versioning.create_project_snapshot(project.id, user.id, title: "Second")

      snapshots = Versioning.list_project_snapshots(project.id)
      assert length(snapshots) == 2
      assert hd(snapshots).title == "Second"
    end

    test "preloads created_by", %{project: project, user: user} do
      {:ok, _} = Versioning.create_project_snapshot(project.id, user.id)

      [snapshot] = Versioning.list_project_snapshots(project.id)
      assert snapshot.created_by.id == user.id
    end

    test "respects limit and offset", %{project: project, user: user} do
      for _ <- 1..3, do: Versioning.create_project_snapshot(project.id, user.id)

      assert length(Versioning.list_project_snapshots(project.id, limit: 2)) == 2
      assert length(Versioning.list_project_snapshots(project.id, limit: 2, offset: 2)) == 1
    end
  end

  describe "get_project_snapshot/2" do
    test "returns snapshot by id", %{project: project, user: user} do
      {:ok, created} = Versioning.create_project_snapshot(project.id, user.id, title: "Test")

      snapshot = Versioning.get_project_snapshot(project.id, created.id)
      assert snapshot.id == created.id
      assert snapshot.title == "Test"
    end

    test "returns nil for non-existent snapshot", %{project: project} do
      assert Versioning.get_project_snapshot(project.id, 999_999) == nil
    end
  end

  describe "count_project_snapshots/1" do
    test "counts snapshots for project", %{project: project, user: user} do
      assert Versioning.count_project_snapshots(project.id) == 0

      {:ok, _} = Versioning.create_project_snapshot(project.id, user.id)
      assert Versioning.count_project_snapshots(project.id) == 1

      {:ok, _} = Versioning.create_project_snapshot(project.id, user.id)
      assert Versioning.count_project_snapshots(project.id) == 2
    end
  end

  describe "update_project_snapshot/2" do
    test "updates title and description", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

      assert {:ok, updated} =
               Versioning.update_project_snapshot(snapshot, %{
                 title: "Renamed",
                 description: "Updated"
               })

      assert updated.title == "Renamed"
      assert updated.description == "Updated"
    end

    test "returns error changeset for invalid attrs", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

      assert {:error, %Ecto.Changeset{}} =
               Versioning.update_project_snapshot(snapshot, %{
                 title: String.duplicate("a", 256)
               })
    end
  end

  describe "delete_project_snapshot/1" do
    test "deletes snapshot and cleans up storage", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)
      assert {:ok, _} = Versioning.delete_project_snapshot(snapshot)
      assert Versioning.count_project_snapshots(project.id) == 0
    end
  end

  describe "restore_project_snapshot/3" do
    test "restores entities from snapshot", %{project: project, user: user, sheet: sheet} do
      # Create snapshot with current state
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Baseline")

      # Modify the sheet
      {:ok, _} = Storyarn.Sheets.update_sheet(sheet, %{name: "Modified Name"})

      # Restore from snapshot
      assert {:ok, result} =
               Versioning.restore_project_snapshot(project.id, snapshot, user_id: user.id)

      assert result.restored >= 1
      assert is_integer(result.skipped)

      # Verify sheet was restored
      restored_sheet = Storyarn.Sheets.get_sheet(project.id, sheet.id)
      assert restored_sheet.name == sheet.name
    end

    test "creates safety snapshots when user_id provided", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Base")

      initial_count = Versioning.count_project_snapshots(project.id)

      {:ok, _} = Versioning.restore_project_snapshot(project.id, snapshot, user_id: user.id)

      # Should have 2 more: pre-restore + post-restore
      assert Versioning.count_project_snapshots(project.id) == initial_count + 2
    end

    test "keeps the committed restore successful when the best-effort post snapshot fails", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(
          project.id,
          user.id,
          title: "Post-snapshot failure boundary"
        )

      failures = [
        {:raise, fn _project_id, _user_id, _opts -> raise "post snapshot raised" end},
        {:throw, fn _project_id, _user_id, _opts -> throw(:post_snapshot_thrown) end},
        {:exit, fn _project_id, _user_id, _opts -> exit(:post_snapshot_exited) end}
      ]

      Enum.each(failures, fn {failure_kind, post_snapshot_fun} ->
        current_name = "Current before #{failure_kind}"
        {:ok, _sheet} = Storyarn.Sheets.update_sheet(sheet, %{name: current_name})
        snapshot_count = Versioning.count_project_snapshots(project.id)

        assert {:ok, result} =
                 Versioning.restore_project_snapshot(
                   project.id,
                   snapshot,
                   user_id: user.id,
                   __post_restore_snapshot_fun: post_snapshot_fun
                 )

        assert result.restored >= 1
        assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name == sheet.name

        # The mandatory safety snapshot is durable; only the best-effort
        # post-restore artifact is absent.
        assert Versioning.count_project_snapshots(project.id) ==
                 snapshot_count + 1
      end)
    end

    test "restores snapshot entities directly from trash", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

      # Soft-delete the sheet
      {:ok, _deleted_sheet} = Storyarn.Sheets.delete_sheet(sheet)
      assert Storyarn.Sheets.get_sheet(project.id, sheet.id) == nil

      assert {:ok, result} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id
               )

      assert result.restored >= 1
      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).id == sheet.id
    end

    test "the durable safety snapshot directly reverses a destructive restore with the same child IDs", %{
      project: project,
      user: user,
      sheet: sheet,
      flow: flow
    } do
      {:ok, target_snapshot} =
        Versioning.create_project_snapshot(
          project.id,
          user.id,
          title: "Target before current children"
        )

      current_block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Current-only block"}
        })

      current_node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "current_only_safety_node"}
        })

      assert {:ok, _result} =
               Versioning.restore_project_snapshot(
                 project.id,
                 target_snapshot,
                 user_id: user.id
               )

      assert %Block{deleted_at: %DateTime{}} =
               Repo.get!(Block, current_block.id)

      assert %FlowNode{deleted_at: %DateTime{}} =
               Repo.get!(FlowNode, current_node.id)

      safety_snapshot =
        project.id
        |> Versioning.list_project_snapshots()
        |> Enum.find(fn snapshot ->
          snapshot.title ==
            "Before restore to project snapshot v#{target_snapshot.version_number}"
        end)

      assert %ProjectSnapshot{} = safety_snapshot

      assert {:ok, _result} =
               Versioning.restore_project_snapshot(
                 project.id,
                 safety_snapshot,
                 user_id: user.id
               )

      assert %Block{id: block_id, deleted_at: nil} =
               Repo.get!(Block, current_block.id)

      assert %FlowNode{id: node_id, deleted_at: nil} =
               Repo.get!(FlowNode, current_node.id)

      assert block_id == current_block.id
      assert node_id == current_node.id
    end

    test "requires an actor before creating a safety snapshot", %{
      project: project,
      user: user
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id)

      snapshot_count = Versioning.count_project_snapshots(project.id)

      assert {:error, :restore_user_required} =
               Versioning.restore_project_snapshot(project.id, snapshot)

      assert Versioning.count_project_snapshots(project.id) == snapshot_count
    end

    test "aborts when the mandatory pre-restore snapshot cannot be created", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id)

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Current state"})

      snapshot_count = Versioning.count_project_snapshots(project.id)

      assert {:error, {:pre_restore_snapshot_failed, :storage_unavailable}} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id,
                 __pre_restore_snapshot_fun: fn
                   _project_id, _user_id, _opts ->
                     {:error, :storage_unavailable}
                 end
               )

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name ==
               "Current state"

      assert Versioning.count_project_snapshots(project.id) == snapshot_count
    end

    test "reads back and verifies the pre-restore snapshot checksum", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id)

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Current state"})

      corrupted_checksum = String.duplicate("0", 64)
      snapshot_count = Versioning.count_project_snapshots(project.id)

      create_corrupted_snapshot = fn project_id, user_id, opts ->
        with {:ok, pre_snapshot} <-
               Versioning.create_project_snapshot(project_id, user_id, opts) do
          Repo.update_all(
            from(s in ProjectSnapshot, where: s.id == ^pre_snapshot.id),
            set: [checksum: corrupted_checksum]
          )

          {:ok, pre_snapshot}
        end
      end

      assert {:error, {:pre_restore_snapshot_failed, {:checksum_mismatch, ^corrupted_checksum, actual_checksum}}} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id,
                 __pre_restore_snapshot_fun: create_corrupted_snapshot
               )

      refute actual_checksum == corrupted_checksum

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name ==
               "Current state"

      assert Versioning.count_project_snapshots(project.id) ==
               snapshot_count + 1
    end

    test "reads back and verifies the pre-restore snapshot entity counts", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id)

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Current state"})

      snapshot_count = Versioning.count_project_snapshots(project.id)

      create_snapshot_with_invalid_counts = fn project_id, user_id, opts ->
        with {:ok, pre_snapshot} <-
               Versioning.create_project_snapshot(project_id, user_id, opts) do
          invalid_counts =
            Map.update!(
              pre_snapshot.entity_counts,
              "sheets",
              &(&1 + 1)
            )

          Repo.update_all(
            from(s in ProjectSnapshot, where: s.id == ^pre_snapshot.id),
            set: [entity_counts: invalid_counts]
          )

          {:ok, pre_snapshot}
        end
      end

      assert {:error,
              {:pre_restore_snapshot_failed,
               {:persisted_project_snapshot_entity_count_mismatch, "sheets", persisted_count, actual_count}}} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id,
                 __pre_restore_snapshot_fun: create_snapshot_with_invalid_counts
               )

      assert persisted_count == actual_count + 1

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name ==
               "Current state"

      assert Versioning.count_project_snapshots(project.id) ==
               snapshot_count + 1
    end

    test "rejects an enclosing transaction before creating safety snapshot rows or blobs", %{
      project: project,
      user: user
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Transaction boundary")

      snapshot_count = Versioning.count_project_snapshots(project.id)
      stored_paths = stored_snapshot_paths(project.id)

      assert {:ok, {:error, :project_snapshot_restore_transaction_owner_required}} =
               Repo.transaction(fn ->
                 Versioning.restore_project_snapshot(
                   project.id,
                   snapshot,
                   user_id: user.id
                 )
               end)

      assert Versioning.count_project_snapshots(project.id) == snapshot_count
      assert stored_snapshot_paths(project.id) == stored_paths
    end

    test "rejects a same-cardinality tampered blob with a different compressed size", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Checksum boundary")

      assert {:ok, snapshot_data} =
               SnapshotStorage.load_snapshot(snapshot.storage_key)

      tampered_data =
        put_in(
          snapshot_data,
          ["sheets", Access.at(0), "snapshot", "name"],
          "Tampered snapshot name"
        )

      assert {:ok, _size} =
               SnapshotStorage.store_raw(snapshot.storage_key, tampered_data)

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Current state"})

      snapshot_count = Versioning.count_project_snapshots(project.id)

      assert {:error, {:compressed_size_mismatch, expected_size, actual_size}} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id
               )

      assert expected_size == snapshot.snapshot_size_bytes
      refute actual_size == expected_size
      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name == "Current state"
      assert Versioning.count_project_snapshots(project.id) == snapshot_count
    end

    test "rejects a same-size tampered blob by checksum before safety snapshots or mutation", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(
          project.id,
          user.id,
          title: "Same-size checksum boundary"
        )

      assert {:ok, compressed} = Storage.download(snapshot.storage_key)
      <<first_byte, rest::binary>> = compressed
      tampered_compressed = <<Bitwise.bxor(first_byte, 1), rest::binary>>

      assert byte_size(tampered_compressed) == snapshot.snapshot_size_bytes

      assert {:ok, _url} =
               Storage.upload(
                 snapshot.storage_key,
                 tampered_compressed,
                 "application/gzip"
               )

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Current state"})

      snapshot_count = Versioning.count_project_snapshots(project.id)

      assert {:error, {:checksum_mismatch, expected_checksum, actual_checksum}} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id
               )

      assert expected_checksum == snapshot.checksum
      refute actual_checksum == expected_checksum
      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name == "Current state"
      assert Versioning.count_project_snapshots(project.id) == snapshot_count
    end

    test "rejects a snapshot owned by another project before safety snapshots", %{
      project: source_project,
      user: user
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(source_project.id, user.id, title: "Private source")

      destination_project = project_fixture(user)
      destination_sheet = sheet_fixture(destination_project, %{name: "Destination state"})

      source_count = Versioning.count_project_snapshots(source_project.id)
      destination_count = Versioning.count_project_snapshots(destination_project.id)

      assert {:error, :snapshot_project_mismatch} =
               Versioning.restore_project_snapshot(
                 destination_project.id,
                 snapshot,
                 user_id: user.id
               )

      forged_snapshot = %{snapshot | project_id: destination_project.id}

      assert {:error, :snapshot_project_mismatch} =
               Versioning.restore_project_snapshot(
                 destination_project.id,
                 forged_snapshot,
                 user_id: user.id
               )

      assert Versioning.count_project_snapshots(source_project.id) == source_count
      assert Versioning.count_project_snapshots(destination_project.id) == destination_count

      assert Storyarn.Sheets.get_sheet(destination_project.id, destination_sheet.id).name ==
               "Destination state"
    end

    test "rejects a storage key that is not bound to the snapshot identity before mutation", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Bound storage identity")

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Current state"})

      forged_key =
        SnapshotStorage.build_project_key(
          project.id,
          snapshot.version_number + 1,
          "0123456789abcdef"
        )

      Repo.update_all(
        from(candidate in ProjectSnapshot, where: candidate.id == ^snapshot.id),
        set: [storage_key: forged_key]
      )

      snapshot_count = Versioning.count_project_snapshots(project.id)

      assert {:error, :project_snapshot_storage_key_mismatch} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id
               )

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name == "Current state"
      assert Versioning.count_project_snapshots(project.id) == snapshot_count
    end

    test "aborts atomically when the project changes after the safety snapshot", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Restore target")

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "State captured for safety"})

      snapshot_count = Versioning.count_project_snapshots(project.id)

      create_then_change_project = fn project_id, user_id, opts ->
        with {:ok, pre_restore_snapshot} <-
               Versioning.create_project_snapshot(project_id, user_id, opts),
             {:ok, _sheet} <-
               Storyarn.Sheets.update_sheet(sheet, %{
                 name: "Concurrent state after safety"
               }) do
          {:ok, pre_restore_snapshot}
        end
      end

      assert {:error, :project_changed_since_pre_restore_snapshot} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id,
                 __pre_restore_snapshot_fun: create_then_change_project
               )

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name ==
               "Concurrent state after safety"

      assert Versioning.count_project_snapshots(project.id) ==
               snapshot_count + 1
    end

    test "aborts without mutation when the verified safety record is deleted before the builder", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(
          project.id,
          user.id,
          title: "Restore target"
        )

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{
          name: "Current state"
        })

      snapshot_count = Versioning.count_project_snapshots(project.id)
      test_pid = self()

      delete_verified_safety_snapshot = fn safety_snapshot ->
        send(test_pid, {:verified_safety_snapshot, safety_snapshot.id})
        {:ok, _deleted} = Versioning.delete_project_snapshot(safety_snapshot)
      end

      assert {:error, :pre_restore_snapshot_not_durable} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id,
                 __after_pre_restore_snapshot_verified_hook: delete_verified_safety_snapshot
               )

      assert_received {:verified_safety_snapshot, safety_snapshot_id}
      refute Versioning.get_project_snapshot(project.id, safety_snapshot_id)

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name ==
               "Current state"

      assert Versioning.count_project_snapshots(project.id) ==
               snapshot_count
    end

    test "accepts a verified safety snapshot with serialized DateTime fields", %{
      project: project,
      user: user,
      sheet: sheet,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Timestamped source", "responses" => []}
        })

      text =
        Localization.get_text_by_source(
          "flow_node",
          node.id,
          "text",
          "es"
        )

      assert {:ok, translated_text} =
               Localization.update_text(text, %{
                 translated_text: "Fuente con fecha",
                 status: "final"
               })

      assert %DateTime{} = translated_text.last_translated_at
      assert %DateTime{} = translated_text.last_reviewed_at

      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Timestamped target")

      {:ok, _sheet} =
        Storyarn.Sheets.update_sheet(sheet, %{name: "Changed after target"})

      assert {:ok, _result} =
               Versioning.restore_project_snapshot(
                 project.id,
                 snapshot,
                 user_id: user.id
               )

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).name == sheet.name
    end
  end

  defp stored_snapshot_paths(project_id) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/#{project_id}/snapshots/project/*")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
