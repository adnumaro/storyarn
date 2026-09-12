defmodule Storyarn.Ideation.ReferenceRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Revision
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.IdeationDestinations
  alias Storyarn.Projects.Versioning.ProjectRecovery
  alias Storyarn.Sheets.Sheet

  setup do
    ctx = ideation_fixture()
    sheet = sheet_fixture(ctx.project, %{name: "Historical character", description: "Original overview"})
    reference = add(ctx, "sheet", sheet.id)
    Map.merge(ctx, %{sheet: sheet, reference: reference})
  end

  test "sealed references and immutable context revisions survive physical deletion and reuse generations", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})
    idea_reference = add(ctx, "sheet", ctx.sheet.id, idea.id)
    original = Repo.get!(Reference, ctx.reference.id)
    ctx.sheet |> Ecto.Changeset.change(description: "Revised overview") |> Repo.update!()

    assert {:ok, refreshed} =
             Ideation.refresh_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               original.id,
               1,
               Ecto.UUID.generate()
             )

    capsule = capture(ctx)
    assert {:ok, %{"version" => 5, "rows" => rows}} = Capsule.open(capsule)
    assert length(rows["references"]) == 2
    assert length(rows["reference_revisions"]) == 3
    refute Jason.encode!(capsule) =~ "Original overview"
    refute Map.has_key?(rows, "comments")
    delete_sessions(ctx)
    maps = restore(ctx, capsule)
    restored = Repo.get!(Reference, maps["references"][original.id])
    assert restored.id != original.id
    assert restored.version == refreshed.version
    assert restored.target_id == ctx.sheet.id
    assert restored.target_identity == original.target_identity
    assert restored.created_by_id == ctx.author.user.id
    assert restored.context["overview"]["description"] == "Revised overview"

    revisions = Repo.all(from r in Revision, where: r.reference_id == ^restored.id, order_by: r.number)
    assert Enum.map(revisions, & &1.operation) == ~w(create refresh)
    assert hd(revisions).context == original.context
    assert Enum.all?(revisions, &(&1.session_id == restored.session_id and &1.actor_id == ctx.author.user.id))
    assert Repo.get!(Reference, maps["references"][idea_reference.id]).idea_id == maps["ideas"][idea.id]

    for _ <- 1..3, do: assert(restore(ctx, capsule) == maps)
    assert Repo.aggregate(Reference, :count) == 2
    assert Repo.aggregate(Revision, :count) == 3
  end

  test "Project materialization rebinds exact Sheet Flow and Scene identities without rewriting history", ctx do
    flow = flow_fixture(ctx.project)
    scene = scene_fixture(ctx.project)
    flow_reference = add(ctx, "flow", flow.id)
    scene_reference = add(ctx, "scene", scene.id)
    original_context = Repo.get!(Reference, flow_reference.id).context
    target = project_fixture(ctx.owner.user)
    snapshot = snapshot(ctx)

    assert {:ok, result} =
             Repo.transact(fn ->
               ProjectRecovery.materialize_into_project(target, snapshot, ctx.owner.user.id, %{},
                 localization_scope: :active,
                 materialization_mode: :exact,
                 preserved_localization_actor_ids: MapSet.new()
               )
             end)

    maps = result.id_maps.ideation

    for {reference, type, old_id} <- [
          {ctx.reference, :sheet, ctx.sheet.id},
          {flow_reference, :flow, flow.id},
          {scene_reference, :scene, scene.id}
        ] do
      restored = Repo.get!(Reference, maps["references"][reference.id])
      assert restored.target_id == result.id_maps[type][old_id]
      assert restored.target_id != old_id
      assert restored.target_identity == maps["content_destinations"][Atom.to_string(type)][old_id].identity
    end

    assert Repo.get!(Reference, maps["references"][flow_reference.id]).context == original_context

    assert {:ok, %{references: references}} =
             Ideation.list_references(ctx.owner, target.id, maps["sessions"][ctx.session.id], nil)

    assert length(references) == 3
    assert Enum.all?(references, &(&1.status in ~w(current changed)))
  end

  test "an unavailable source generation cannot be resurrected by an exact numeric destination map", ctx do
    original = Repo.get!(Reference, ctx.reference.id)
    stale_identity = "created:2000-01-01T00:00:00Z"
    Repo.update_all(from(r in Reference, where: r.id == ^original.id), set: [target_identity: stale_identity])
    capsule = capture(ctx)
    assert {:ok, data} = Capsule.open(capsule)
    [captured] = data["rows"]["references"]
    assert captured["target_id"] == nil
    assert captured["target_identity"] == stale_identity
    assert captured["context"] == original.context

    # The existing generation can be reused, but its stale numeric link must be
    # detached in persistence as well as in the normalized recovery image.
    maps = restore(ctx, capsule)
    assert maps["references"][original.id] == original.id
    assert Repo.get!(Reference, original.id).target_id == nil

    target = project_fixture(ctx.owner.user)
    snapshot = snapshot(ctx)

    assert {:ok, result} =
             Repo.transact(fn ->
               ProjectRecovery.materialize_into_project(target, snapshot, ctx.owner.user.id, %{},
                 localization_scope: :active,
                 materialization_mode: :exact,
                 preserved_localization_actor_ids: MapSet.new()
               )
             end)

    assert result.id_maps.sheet[ctx.sheet.id]
    reference = Repo.get!(Reference, result.id_maps.ideation["references"][original.id])
    assert reference.target_id == nil
    assert reference.target_identity == stale_identity
    assert reference.context == original.context

    assert {:ok, %{references: [%{status: "unavailable", base: nil, current: nil}]}} =
             Ideation.list_references(ctx.owner, target.id, reference.session_id, nil)
  end

  test "capture preserves matching tombstone identities while detaching physically missing targets", ctx do
    original = Repo.get!(Reference, ctx.reference.id)
    assert {:ok, _} = Storyarn.Sheets.delete_sheet(ctx.author, ctx.sheet)
    assert {:ok, data} = ctx |> capture() |> Capsule.open()
    assert hd(data["rows"]["references"])["target_id"] == ctx.sheet.id
    Repo.delete!(ctx.sheet)
    assert {:ok, data} = ctx |> capture() |> Capsule.open()
    captured = hd(data["rows"]["references"])
    assert captured["target_id"] == nil
    assert captured["context"] == original.context
    assert captured["target_identity"] == original.target_identity
  end

  test "a destination removed after capture does not block direct recovery or expose saved context", ctx do
    original = Repo.get!(Reference, ctx.reference.id)
    capsule = capture(ctx)
    Repo.delete!(ctx.sheet)
    maps = restore(ctx, capsule)
    restored = Repo.get!(Reference, maps["references"][original.id])
    assert restored.id == original.id
    assert restored.target_id == nil
    assert restored.target_identity == original.target_identity
    assert restored.context == original.context

    assert {:ok, %{references: [%{status: "unavailable", base: nil, current: nil}]}} =
             Ideation.list_references(ctx.owner, ctx.project.id, restored.session_id, nil)

    assert restore(ctx, capsule) == maps
  end

  test "direct identity receipts do not rebind another retained reference to the same numeric target", ctx do
    assert {:ok, second} =
             Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, %{
               target_type: "sheet",
               target_id: ctx.sheet.id,
               relation: "affects",
               request_key: Ecto.UUID.generate()
             })

    {:ok, data} = ctx |> capture() |> Capsule.open()
    new_identity = "created:2000-01-01T00:00:00Z"

    data =
      update_in(data, ["rows", "references"], fn entries ->
        Enum.map(entries, fn row ->
          if row["id"] == second.id, do: Map.put(row, "target_identity", new_identity), else: row
        end)
      end)

    assert {:ok, capsule} = Capsule.seal(data)

    Repo.update_all(from(s in Sheet, where: s.id == ^ctx.sheet.id),
      set: [inserted_at: ~U[2000-01-01 00:00:00Z]]
    )

    maps = restore(ctx, capsule)
    assert Repo.get!(Reference, maps["references"][ctx.reference.id]).target_id == nil
    assert Repo.get!(Reference, maps["references"][second.id]).target_id == ctx.sheet.id
    assert restore(ctx, capsule) == maps
  end

  test "a generation changed after capture stays unavailable through direct recovery", ctx do
    original = Repo.get!(Reference, ctx.reference.id)
    capsule = capture(ctx)

    Repo.update_all(from(s in Sheet, where: s.id == ^ctx.sheet.id),
      set: [inserted_at: ~U[2000-01-01 00:00:00Z]]
    )

    delete_sessions(ctx)
    maps = restore(ctx, capsule)
    restored = Repo.get!(Reference, maps["references"][original.id])
    assert restored.target_id == nil
    assert restored.target_identity == original.target_identity
    assert restore(ctx, capsule) == maps
  end

  test "asset receipts rebind only exact same-project destination rows and never name matches", ctx do
    source = asset_fixture(ctx.project, ctx.owner.user)
    reference = add(ctx, "asset", source.id)
    replacement = asset_fixture(ctx.project, ctx.owner.user, %{filename: source.filename})
    other_project = project_fixture(ctx.owner.user)
    foreign = asset_fixture(other_project, ctx.owner.user)
    capsule = capture(ctx)
    delete_sessions(ctx)
    destinations = IdeationDestinations.build(ctx.project.id, %{}, %{source.id => replacement.id})
    maps = restore(ctx, capsule, destinations)
    assert Repo.get!(Reference, maps["references"][reference.id]).target_id == replacement.id
    assert Repo.get!(Reference, maps["references"][ctx.reference.id]).target_id == nil
    assert IdeationDestinations.build(ctx.project.id, %{}, %{source.id => foreign.id})["asset"] == %{}
  end

  test "unmapped localization targets retain private recovery context but expose no historical preview", ctx do
    text = localized_text_fixture(ctx.project.id)
    reference = add(ctx, "localization", text.id)
    original = Repo.get!(Reference, reference.id)
    capsule = capture(ctx)
    delete_sessions(ctx)
    destinations = IdeationDestinations.build(ctx.project.id, %{}, %{})
    maps = restore(ctx, capsule, destinations)
    restored = Repo.get!(Reference, maps["references"][reference.id])
    assert restored.target_id == nil
    assert restored.target_identity == original.target_identity
    assert restored.context == original.context

    assert {:ok, %{references: references}} =
             Ideation.list_references(ctx.owner, ctx.project.id, maps["sessions"][ctx.session.id], nil)

    assert Enum.all?(references, &(&1.status == "unavailable" and is_nil(&1.base) and is_nil(&1.current)))

    assert {:error, :not_found} =
             Ideation.reference_history(ctx.owner, ctx.project.id, restored.session_id, nil, restored.id)

    assert restore(ctx, capsule, destinations) == maps
  end

  test "cross-project direct recovery detaches targets without granting original actors membership", ctx do
    target = project_fixture(ctx.owner.user)
    capsule = capture(ctx)
    maps = restore(%{ctx | project: target}, capsule)
    restored = Repo.get!(Reference, maps["references"][ctx.reference.id])
    assert restored.target_id == nil
    assert restored.created_by_id == ctx.author.user.id
    assert {:error, :not_found} = Ideation.list_references(ctx.author, target.id, restored.session_id, nil)
  end

  test "removed references and missing actor identities survive recovery without reviving the link", ctx do
    assert {:ok, _} =
             Ideation.remove_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               ctx.reference.id,
               1,
               Ecto.UUID.generate()
             )

    capsule = capture(ctx)
    Repo.delete!(ctx.author.user)
    delete_sessions(ctx)
    maps = restore(ctx, capsule)
    restored = Repo.get!(Reference, maps["references"][ctx.reference.id])
    assert restored.deleted_at
    assert restored.created_by_id == nil
    assert restored.version == 2
    assert Enum.all?(Repo.all(Revision), &is_nil(&1.actor_id))
    assert {:ok, %{references: []}} = Ideation.list_references(ctx.owner, ctx.project.id, restored.session_id, nil)
    assert restore(ctx, capsule) == maps
  end

  test "version four capsules normalize empty references without dropping their other history", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()
    legacy = data |> Map.put("version", 4) |> update_in(["rows"], &Map.drop(&1, ~w(references reference_revisions)))
    assert {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["version"] == 5
    assert normalized["rows"]["references"] == []
    assert normalized["rows"]["reference_revisions"] == []
    maps = restore(ctx, capsule)
    assert maps["references"] == %{}
    assert Repo.aggregate(Reference, :count) == 1
    assert restore(ctx, capsule) == maps
  end

  test "authenticated malformed reference graphs are rejected before replacing a live session", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()

    mutations = [
      {"references", "session_id", -1},
      {"references", "idea_id", -1},
      {"references", "target_type", "unsupported"},
      {"references", "target_id", 0},
      {"references", "target_identity", "name:Historical character"},
      {"references", "relation", "unknown"},
      {"references", "version", 51},
      {"references", "created_by_id", "actor"},
      {"references", "context", %{"preview" => "unexpected"}},
      {"references", "deleted_at", "2026-09-12T12:00:00.000000"},
      {"reference_revisions", "reference_id", -1},
      {"reference_revisions", "session_id", -1},
      {"reference_revisions", "number", 2},
      {"reference_revisions", "operation", "refresh"},
      {"reference_revisions", "request_key", Base.encode64("bad")},
      {"reference_revisions", "fingerprint", Base.encode64("bad")}
    ]

    for {collection, key, value} <- mutations do
      invalid = update_in(data, ["rows", collection], fn [row] -> [Map.put(row, key, value)] end)
      assert {:error, :ideation_recovery_capture_failed} = Capsule.seal(invalid)
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(invalid), nil)
      assert Repo.get!(Session, ctx.session.id).deleted_at == nil
    end
  end

  test "history consistency rejects forged overviews, duplicate targets and replay keys", ctx do
    other = sheet_fixture(ctx.project)
    add(ctx, "sheet", other.id)
    {:ok, data} = ctx |> capture() |> Capsule.open()
    [first, second] = data["rows"]["references"]
    [first_revision, second_revision] = data["rows"]["reference_revisions"]

    changed_context = put_in(first, ["context", "overview", "description"], "Changed without a revision")
    duplicate_target = Map.put(second, "target_id", first["target_id"])
    duplicate_receipt = Map.put(second_revision, "request_key", first_revision["request_key"])

    invalid_inventories = [
      put_in(data, ["rows", "references"], [changed_context, second]),
      put_in(data, ["rows", "references"], [first, duplicate_target]),
      put_in(data, ["rows", "reference_revisions"], [first_revision, duplicate_receipt])
    ]

    for invalid <- invalid_inventories do
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(invalid), nil)
      assert Repo.get!(Session, ctx.session.id).deleted_at == nil
    end
  end

  defp add(ctx, type, target_id, idea_id \\ nil) do
    assert {:ok, reference} =
             Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, idea_id, %{
               target_type: type,
               target_id: target_id,
               relation: "reference",
               request_key: Ecto.UUID.generate()
             })

    reference
  end

  defp capture(ctx) do
    assert {:ok, capsule} =
             Repo.transact(fn ->
               lock_project(ctx.project.id)
               Ideation.capture_recovery(ctx.project.id)
             end)

    capsule
  end

  defp snapshot(ctx) do
    {:ok, data} =
      Repo.transact(fn ->
        {:ok,
         ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
      end)

    data |> Map.put("asset_catalog_refs", %{}) |> Jason.encode!() |> Jason.decode!()
  end

  defp restore(ctx, capsule, destinations \\ nil) do
    assert {:ok, maps} = restore_result(ctx, capsule, destinations)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    maps
  end

  defp restore_result(ctx, capsule, destinations) do
    Repo.transact(fn ->
      lock_project(ctx.project.id)
      Ideation.restore_recovery(ctx.project.id, capsule, destinations)
    end)
  end

  defp lock_project(id), do: Repo.one!(from p in "projects", where: p.id == ^id, select: p.id, lock: "FOR UPDATE")
  defp delete_sessions(ctx), do: Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)

  defp authenticate(data) do
    {:ok, bytes} = data |> Jason.encode!() |> Vault.encrypt()
    %{"version" => 1, "ciphertext" => Base.encode64(bytes)}
  end
end
