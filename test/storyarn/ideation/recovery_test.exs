defmodule Storyarn.Ideation.RecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.ProjectRecovery
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat

  setup do
    ideation_fixture()
  end

  for {visibility_source, configuration, attrs} <- [
        {:session_default, %{default_visibility: :shared}, %{}},
        {:explicit_choice, %{}, %{visibility: :shared}}
      ] do
    @configuration configuration
    @idea_attributes attrs

    test "captures and restores ideas shared at creation through #{visibility_source}", ctx do
      ctx = configure_session(ctx, @configuration)
      attrs = Map.put(@idea_attributes, :configuration_version, ctx.session.configuration_version)
      idea = idea_fixture(ctx, attrs)
      assert idea.visibility == :shared
      assert idea.published_revision == 1
      operation = Repo.one!(from r in Reveal, where: r.session_id == ^ctx.session.id)
      assert operation.selection == %{"mode" => "creation"}

      assert {:ok, capsule} =
               Repo.transact(fn ->
                 {:ok, _, _} = Projects.authorize_locked(ctx.owner, ctx.project.id, :edit_content)
                 Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
                 Ideation.capture_recovery(ctx.project.id)
               end)

      snapshot = snapshot(ctx)
      assert snapshot["ideation"] == capsule
      assert :ok = SnapshotObjectFormat.validate_project(snapshot)
      Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
      maps = restore(ctx, capsule)
      session_id = maps["sessions"][ctx.session.id]
      idea_id = maps["ideas"][idea.id]
      operation_id = maps["reveals"][operation.id]

      assert {:ok, %{body: "<p>Original idea</p>", revision: 1, visibility: :shared}} =
               Ideation.get_idea(ctx.owner, ctx.project.id, session_id, idea_id)

      restored = Repo.get!(Reveal, operation_id)
      assert restored.selection == %{"mode" => "creation"}
      assert restored.manifest == [%{"idea_id" => idea_id, "revision" => 1}]
      assert restored.status == :completed
      publication = Repo.one!(from p in Publication, where: p.idea_id == ^idea_id)
      assert publication.operation_id == operation_id
      assert publication.revision == 1
      assert :ok = ctx |> snapshot() |> SnapshotObjectFormat.validate_project()
    end
  end

  test "filtered assisted reveal selections survive capture and restore", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    attrs = %{publication_consent: :facilitator_assisted, configuration_version: ctx.session.configuration_version}
    idea = idea_fixture(ctx, attrs)
    idea_fixture(ctx, Map.put(attrs, :state, :discarded))

    {:ok, operation} =
      Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), %{
        states: [:active, :parked]
      })

    assert operation.manifest == [%{"idea_id" => idea.id, "revision" => 1}]
    capsule = snapshot(ctx)["ideation"]
    assert :ok = Ideation.validate_recovery(capsule)
    maps = restore(ctx, capsule)
    restored = Repo.get!(Reveal, maps["reveals"][operation.id])
    assert restored.selection == %{"mode" => "eligible", "states" => ["active", "parked"]}
    assert restored.manifest == [%{"idea_id" => maps["ideas"][idea.id], "revision" => 1}]
  end

  test "canonical capture includes an authenticated compartment; templates exclude it", ctx do
    idea_fixture(ctx, %{body: "<p>Private motive never visible in a download</p>"})
    snapshot = snapshot(ctx)
    assert snapshot["format_version"] == 3
    assert :ok = SnapshotObjectFormat.validate_project(snapshot)
    encoded = Jason.encode!(snapshot)
    refute encoded =~ "Private motive"
    refute encoded =~ "publication_consent"
    refute encoded =~ "author_id"
    assert snapshot["ideation"]["version"] == 1
    assert {:ok, capsule_json} = Base.decode64(snapshot["ideation"]["ciphertext"])
    refute capsule_json =~ "Private motive"
    template = ProjectSnapshotBuilder.build_snapshot(ctx.project.id)
    assert template["format_version"] == 2
    refute Map.has_key?(template, "ideation")
  end

  test "restores private history, conflicts, publication and sources after deleting original records", ctx do
    private = idea_fixture(ctx, %{title: "Hidden", body: "<p>Private motive</p>"})
    shared = ctx |> idea_fixture(%{title: "Published", body: "<p>Original public</p>"}) |> then(&publish_idea(ctx, &1))

    assert {:ok, shared_head} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               shared.id,
               1,
               edit_attrs(%{body: "<p>Unpublished next revision</p>"})
             )

    conflict_attrs = edit_attrs(%{body: "<p>Conflicting private input</p>"})

    assert {:error, {:edit_conflict, conflict}} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, shared.id, 1, conflict_attrs)

    attrs = idea_attrs(%{body: "<p>Derived privately</p>"})
    # Simulate provenance written by the former derivation feature. Existing capsules
    # must retain and remap it although the creation API has been removed.
    derived = idea_fixture(ctx, attrs)

    Idea
    |> Repo.get!(derived.id)
    |> Ecto.Changeset.change(source_idea_id: shared.id, creation_source_id: shared.id, source_revision: 1)
    |> Repo.update!()

    snapshot = snapshot(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, snapshot["ideation"])
    session_id = maps["sessions"][ctx.session.id]
    private_id = maps["ideas"][private.id]
    shared_id = maps["ideas"][shared.id]

    assert {:ok, %{body: "<p>Private motive</p>", author_id: author_id}} =
             Ideation.get_idea(ctx.author, ctx.project.id, session_id, private_id)

    assert author_id == ctx.author.user.id
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, session_id, private_id)

    assert {:ok, %{body: "<p>Original public</p>", revision: 1}} =
             Ideation.get_idea(ctx.owner, ctx.project.id, session_id, shared_id)

    assert {:ok, %{body: "<p>Unpublished next revision</p>", revision: revision}} =
             Ideation.get_idea(ctx.author, ctx.project.id, session_id, shared_id)

    assert revision == shared_head.revision

    assert Repo.get!(Storyarn.Ideation.Ideas.Edit, maps["edits"][conflict.id]).body ==
             "<p>Conflicting private input</p>"

    assert {:error, {:edit_conflict, %{id: conflict_id}}} =
             Ideation.update_idea(ctx.author, ctx.project.id, session_id, shared_id, 1, conflict_attrs)

    assert conflict_id == maps["edits"][conflict.id]

    assert {:ok, %{id: derived_id, source_idea_id: ^shared_id, source_revision: 1}} =
             Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][derived.id])

    assert derived_id == maps["ideas"][derived.id]
  end

  test "missing authors remain closed and are never reassigned to the restoring owner", ctx do
    private = idea_fixture(ctx)
    snapshot = snapshot(ctx)
    Repo.delete!(ctx.author.user)
    maps = restore(ctx, snapshot["ideation"])
    session_id = maps["sessions"][ctx.session.id]
    private_id = maps["ideas"][private.id]
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, session_id, private_id)
    assert Repo.one(from i in "ideation_ideas", where: i.id == ^private_id, select: i.author_id) == nil
    assert Repo.exists?(from r in "ideation_idea_revisions", where: r.idea_id == ^private_id)
  end

  test "stable account identity defeats reused numeric IDs and survives email changes", ctx do
    private = idea_fixture(ctx)
    capsule = snapshot(ctx)["ideation"]
    ctx.author.user |> Ecto.Changeset.change(email: unique_user_email()) |> Repo.update!()
    maps = restore(ctx, capsule)

    assert {:ok, _} =
             Ideation.get_idea(ctx.author, ctx.project.id, maps["sessions"][ctx.session.id], maps["ideas"][private.id])

    old_id = ctx.author.user.id
    Repo.delete!(Repo.get!(User, old_id))
    replacement = %User{id: old_id} |> User.email_changeset(%{email: unique_user_email()}) |> Repo.insert!()
    membership_fixture(ctx.project, replacement, "editor")
    maps = restore(ctx, capsule)

    assert {:error, :not_found} =
             Ideation.get_idea(
               user_scope_fixture(replacement),
               ctx.project.id,
               maps["sessions"][ctx.session.id],
               maps["ideas"][private.id]
             )
  end

  test "replacement keeps the previous session recoverable without exposing drafts", ctx do
    idea = idea_fixture(ctx)
    capsule = snapshot(ctx)["ideation"]

    assert {:ok, _} =
             Ideation.update_session(ctx.owner, ctx.project.id, ctx.session.id, 1, %{title: "Changed since capture"})

    restore(ctx, capsule)
    assert {:error, :not_found} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)
    assert {:error, :not_found} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert {:ok, [replaced]} = Ideation.list_sessions(ctx.owner, ctx.project.id, status: :replaced)
    assert replaced.id == ctx.session.id
    assert {:error, :unauthorized} = Ideation.recover_session(ctx.peer, ctx.project.id, replaced.id, replaced.revision)
    assert {:ok, recovered} = Ideation.recover_session(ctx.owner, ctx.project.id, replaced.id, replaced.revision)
    assert recovered.status == :archived
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, recovered.id, idea.id)
    assert {:ok, _} = Ideation.get_idea(ctx.author, ctx.project.id, recovered.id, idea.id)
  end

  test "tampering and unsupported formats fail before changing any data", ctx do
    idea_fixture(ctx)
    snapshot = snapshot(ctx)
    capsule = snapshot["ideation"]
    invalid = %{capsule | "ciphertext" => Base.encode64("forged capsule")}
    assert {:error, :invalid_ideation_recovery} = restore_result(ctx, invalid)
    assert {:ok, _} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)
    assert {:error, :missing_ideation_recovery} = SnapshotObjectFormat.validate_project(Map.delete(snapshot, "ideation"))

    assert {:error, :unexpected_ideation_recovery} =
             SnapshotObjectFormat.validate_project(%{snapshot | "format_version" => 2})

    assert {:error, :invalid_ideation_recovery} = Ideation.validate_recovery(%{capsule | "version" => 99})
    assert {:error, :legacy_snapshot_excludes_ideation} = restore_result(ctx, nil)
  end

  test "authenticated capsules reject malformed timestamps before replacing current data", ctx do
    assert {:ok, session} =
             Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, %{})

    assert {:ok, _} = Ideation.start_timer(ctx.facilitator, ctx.project.id, session.id, session.revision, %{seconds: 60})
    idea = idea_fixture(ctx, %{visibility: :shared})

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               idea.revision,
               edit_attrs(%{body: "<p>Current text</p>"})
             )

    capsule = snapshot(ctx)["ideation"]
    {:ok, data} = Capsule.open(capsule)

    for {collection, _, _, fields} <- Inventory.tables(),
        field <- fields,
        field in [
          :inserted_at,
          :updated_at,
          :archived_at,
          :deleted_at,
          :completed_at,
          :started_at,
          :closed_at,
          :deadline_at
        ] do
      assert [_ | _] = data["rows"][collection]
      key = Atom.to_string(field)

      values = ["not-a-date", "-9999-01-01T00:00:00", "-4713-01-01T00:00:00"]
      values = values ++ if field in [:inserted_at, :updated_at], do: [nil], else: [42]

      for invalid <- values do
        changed =
          update_in(data, ["rows", collection], fn [row | rest] ->
            [Map.put(row, key, invalid) | rest]
          end)

        # Bypass sealing to exercise validation of an authenticated but invalid archive.
        {:ok, encrypted} = changed |> Jason.encode!() |> Vault.encrypt()
        malformed = %{"version" => 1, "ciphertext" => Base.encode64(encrypted)}
        assert {:error, :invalid_ideation_recovery} = Ideation.validate_recovery(malformed)
        assert {:error, :invalid_ideation_recovery} = restore_result(ctx, malformed)
      end
    end

    assert {:ok, %{body: "<p>Current text</p>"}} =
             Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)

    assert snapshot(ctx)["ideation"] == capsule
  end

  test "the Project materializer integrates recovery and remaps IDs without changing project access", ctx do
    private = idea_fixture(ctx)
    snapshot = snapshot(ctx)
    target = project_fixture(ctx.owner.user)

    assert {:ok, result} =
             Repo.transact(fn ->
               ProjectRecovery.materialize_into_project(target, snapshot, ctx.owner.user.id, %{},
                 localization_scope: :active,
                 materialization_mode: :exact,
                 preserved_localization_actor_ids: MapSet.new()
               )
             end)

    maps = result.id_maps.ideation
    session_id = maps["sessions"][ctx.session.id]
    idea_id = maps["ideas"][private.id]
    assert {:error, _} = Ideation.get_idea(ctx.author, target.id, session_id, idea_id)
    membership_fixture(target, ctx.author.user, "editor")
    assert {:ok, %{author_id: author_id}} = Ideation.get_idea(ctx.author, target.id, session_id, idea_id)
    assert author_id == ctx.author.user.id
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, target.id, session_id, idea_id)
  end

  test "unchanged capture keeps canonical bytes stable and an edit invalidates the cache", ctx do
    idea = idea_fixture(ctx)
    first = snapshot(ctx)
    assert snapshot(ctx) == first

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "<p>A changed draft</p>"})
             )

    refute snapshot(ctx)["ideation"] == first["ideation"]
    assert Repo.aggregate("ideation_recovery_captures", :count, :project_id) == 1
  end

  test "prepared reveals are remapped but not executed during recovery", ctx do
    idea = idea_fixture(ctx)
    key = Ecto.UUID.generate()

    assert {:ok, reveal} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, key, [
               %{idea_id: idea.id, revision: 1}
             ])

    maps = restore(ctx, snapshot(ctx)["ideation"])
    session_id = maps["sessions"][ctx.session.id]
    idea_id = maps["ideas"][idea.id]

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, session_id, key, [%{idea_id: idea_id, revision: 1}])

    assert operation.id == maps["reveals"][reveal.id]
    assert operation.status == :prepared
    assert operation.manifest == [%{"idea_id" => idea_id, "revision" => 1}]
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, session_id, idea_id)
  end

  test "standalone import survives physical deletion of the source project and cache", ctx do
    idea_fixture(ctx, %{body: "<p>Survives source deletion</p>"})
    # The exact archive validator owns the tombstone envelope; use its captured form.
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok,
         ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id,
           localization_scope: :active,
           include_referenced_tombstones: true
         )}
      end)

    snapshot = snapshot |> Map.put("asset_catalog_refs", %{}) |> Jason.encode!() |> Jason.decode!()
    Repo.delete!(ctx.project)
    [[project_id]] = Repo.query!("SELECT nextval(pg_get_serial_sequence('projects', 'id'))").rows

    assert {:ok, recovered} =
             ProjectRecovery.materialize_snapshot_import(ctx.project.workspace_id, snapshot, ctx.owner.user.id,
               snapshot_import_project_id: project_id,
               snapshot_import_asset_catalog_fun: fn _, _, _, _ -> {:ok, %{}} end
             )

    assert {:ok, [session]} = Ideation.list_sessions(ctx.owner, recovered.id)
    membership_fixture(recovered, ctx.author.user, "editor")
    assert {:ok, [%{body: "<p>Survives source deletion</p>"}]} = Ideation.list_ideas(ctx.author, recovered.id, session.id)
    assert {:ok, []} = Ideation.list_ideas(ctx.owner, recovered.id, session.id)
  end

  test "portable template install rejects a recovery compartment", ctx do
    assert {:error, :invalid_project_snapshot_envelope} =
             ProjectRecovery.materialize_template(ctx.project.workspace_id, nil, ctx.owner.user.id)

    assert {:error, :template_excludes_ideation} =
             ProjectRecovery.materialize_template(
               ctx.project.workspace_id,
               snapshot(ctx),
               ctx.owner.user.id
             )

    assert {:error, :ideation_recovery_transaction_required} = Ideation.capture_recovery(ctx.project.id)
    assert {:error, :ideation_recovery_transaction_required} = Ideation.restore_recovery(ctx.project.id, nil)
  end

  test "capture and recovery preserve every row beyond the first read page", ctx do
    for index <- 1..105, do: idea_fixture(ctx, %{body: "<p>Idea #{index}</p>"})
    maps = restore(ctx, snapshot(ctx)["ideation"])
    session_id = maps["sessions"][ctx.session.id]
    assert map_size(maps["ideas"]) == 105
    assert {:ok, ideas} = Ideation.list_ideas(ctx.author, ctx.project.id, session_id, limit: 200)
    assert length(ideas) == 105
    assert Enum.any?(ideas, &(&1.body == "<p>Idea 1</p>"))
    assert Enum.any?(ideas, &(&1.body == "<p>Idea 105</p>"))
  end

  test "cross-project recovery does not transfer authority to reveal private drafts", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})

    idea =
      idea_fixture(ctx, %{
        publication_consent: :facilitator_assisted,
        configuration_version: ctx.session.configuration_version
      })

    snapshot = snapshot(ctx)
    owner = user_scope_fixture(user_fixture())
    target = project_fixture(owner.user)

    assert {:ok, result} =
             Repo.transact(fn ->
               ProjectRecovery.materialize_into_project(target, snapshot, owner.user.id, %{},
                 localization_scope: :active,
                 materialization_mode: :exact,
                 preserved_localization_actor_ids: MapSet.new()
               )
             end)

    maps = result.id_maps.ideation
    session_id = maps["sessions"][ctx.session.id]
    idea_id = maps["ideas"][idea.id]
    assert {:ok, %{manifest: []}} = Ideation.prepare_idea_reveal(owner, target.id, session_id, Ecto.UUID.generate())

    assert {:error, :not_found} =
             Ideation.prepare_idea_reveal(owner, target.id, session_id, Ecto.UUID.generate(), [
               %{idea_id: idea_id, revision: 1}
             ])

    assert {:error, :not_found} = Ideation.get_idea(owner, target.id, session_id, idea_id)
    membership_fixture(target, ctx.author.user, "editor")
    assert {:ok, %{publication_consent: :author_only}} = Ideation.get_idea(ctx.author, target.id, session_id, idea_id)

    same_project_maps = restore(ctx, snapshot["ideation"])

    assert {:ok, %{publication_consent: :facilitator_assisted}} =
             Ideation.get_idea(
               ctx.author,
               ctx.project.id,
               same_project_maps["sessions"][ctx.session.id],
               same_project_maps["ideas"][idea.id]
             )
  end

  test "canvas placement and private connections survive ID remapping and legacy capsules", ctx do
    source = idea_fixture(ctx, %{canvas: %{"x" => -800, "y" => 120, "width" => 320, "color" => "violet"}})
    target = idea_fixture(ctx)
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, true)
    capsule = snapshot(ctx)["ideation"]
    maps = restore(ctx, capsule)
    id = maps["ideas"][source.id]
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, restored} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, id)
    assert restored.canvas["x"] == -800
    assert restored.canvas["width"] == 320
    assert restored.canvas["links"] == [maps["ideas"][target.id]]
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)

    {:ok, data} = Capsule.open(capsule)
    legacy = update_in(data, ["rows", "ideas"], &Enum.map(&1, fn row -> Map.drop(row, ["canvas", "deleted_at"]) end))
    {:ok, legacy_capsule} = Capsule.seal(legacy)
    maps = restore(ctx, legacy_capsule)

    assert {:ok, old} =
             Ideation.get_idea(ctx.author, ctx.project.id, maps["sessions"][ctx.session.id], maps["ideas"][source.id])

    assert old.canvas == %{"links" => []}
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, legacy_capsule, maps)} end)
  end

  test "deleted notes remain deleted after snapshot restore and session private mode is preserved", ctx do
    note = idea_fixture(ctx)
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    capsule = snapshot(ctx)["ideation"]
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:error, :not_found} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][note.id])
    assert {:ok, []} = Ideation.list_ideas(ctx.author, ctx.project.id, session_id, state: :all)
    assert {:ok, session} = Ideation.get_session(ctx.author, ctx.project.id, session_id)
    assert session.configuration.private_mode
    assert Repo.get!(Idea, maps["ideas"][note.id]).deleted_at
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
  end

  defp snapshot(ctx) do
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok, ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
      end)

    snapshot |> Map.put("asset_catalog_refs", %{}) |> Jason.encode!() |> Jason.decode!()
  end

  defp restore(ctx, capsule) do
    assert {:ok, maps} = restore_result(ctx, capsule)
    maps
  end

  defp restore_result(ctx, capsule) do
    Repo.transact(fn ->
      {:ok, _, _} = Projects.authorize_locked(ctx.owner, ctx.project.id, :edit_content)
      Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end
end
