defmodule Storyarn.Ideation.GroupRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Groups.Membership
  alias Storyarn.Ideation.Groups.Revision
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.GraphValidation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    ctx = ideation_fixture()
    first = idea_fixture(ctx, %{visibility: :shared, title: "First source"})
    second = idea_fixture(ctx, %{visibility: :shared, title: "Second source"})
    attrs = group_attrs([first.id, second.id])
    {:ok, group} = Ideation.create_group(ctx.facilitator, ctx.project.id, ctx.session.id, attrs)
    Map.merge(ctx, %{first: first, second: second, group: group, group_attrs: attrs})
  end

  test "captures group history, deleted published sources and receipts after physical deletion", ctx do
    third = idea_fixture(ctx, %{visibility: :shared, title: "Later source"})
    private = idea_fixture(ctx, %{body: "<p>Unpublished source stays private</p>"})
    attrs = edit_attrs(%{idea_ids: [ctx.first.id, third.id], synthesis: "A synthesis that survives its source"})

    assert {:ok, updated} =
             Ideation.update_group(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.group.id, 1, attrs)

    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, third.id, third.revision)
    capsule = capture(ctx)
    assert {:ok, %{"version" => 4, "rows" => rows}} = Capsule.open(capsule)
    assert length(rows["groups"]) == 1
    assert length(rows["group_memberships"]) == 3
    assert length(rows["group_revisions"]) == 2
    refute Jason.encode!(rows) =~ "A synthesis that survives"

    Repo.delete_all(from(s in Session, where: s.project_id == ^ctx.project.id))
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    group_id = maps["groups"][ctx.group.id]
    assert {:ok, [restored]} = Ideation.list_groups(ctx.viewer, ctx.project.id, session_id)
    assert restored.id == group_id
    assert restored.id != ctx.group.id
    assert restored.version == updated.version
    assert restored.title == ctx.group.title
    assert restored.synthesis == updated.synthesis
    assert restored.author_id == ctx.facilitator.user.id
    assert restored.idea_ids == [maps["ideas"][ctx.first.id]]

    memberships = Repo.all(from(m in Membership, where: m.group_id == ^group_id, order_by: m.id))
    assert length(memberships) == 3
    assert Enum.all?(memberships, &(&1.source_revision == 1 and &1.actor_id == ctx.facilitator.user.id))
    assert Enum.count(memberships, &(not is_nil(&1.removed_at))) == 1

    revisions = Repo.all(from(r in Revision, where: r.group_id == ^group_id, order_by: r.number))

    assert Enum.map(revisions, & &1.idea_ids) == [
             [maps["ideas"][ctx.first.id], maps["ideas"][ctx.second.id]],
             [maps["ideas"][ctx.first.id], maps["ideas"][third.id]]
           ]

    for revision <- revisions do
      assert revision.sources == Map.new(revision.idea_ids, &{to_string(&1), 1})
    end

    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, session_id, maps["ideas"][private.id])
    assert {:error, :not_found} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][third.id])

    # The exact retained request remains recognizable even though its original
    # database IDs have disappeared. A retry must not apply the mutation twice.
    assert {:ok, replay} =
             Ideation.update_group(ctx.facilitator, ctx.project.id, session_id, ctx.group.id, 1, attrs)

    assert replay.id == group_id
    assert replay.version == updated.version
    for _ <- 1..3, do: assert(restore(ctx, capsule) == maps)
    assert Repo.aggregate(Group, :count) == 1
    assert Repo.aggregate(Revision, :count) == 2
  end

  test "private-mode recovery keeps retained synthesis hidden before ordinary reads", ctx do
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, session.id, session.revision, true)
    capsule = capture(ctx)
    Repo.delete_all(from(s in Session, where: s.project_id == ^ctx.project.id))
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]

    for actor <- [ctx.author, ctx.viewer, ctx.facilitator, ctx.owner] do
      assert {:ok, []} = Ideation.list_groups(actor, ctx.project.id, session_id)
    end

    assert Repo.get!(Group, maps["groups"][ctx.group.id]).synthesis == ctx.group.synthesis
    assert restore(ctx, capsule) == maps
  end

  test "a deleted group retains its revision and remapped provenance for explicit undo", ctx do
    assert {:ok, deleted} =
             Ideation.delete_group(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.group.id, 1, Ecto.UUID.generate())

    capsule = capture(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    group_id = maps["groups"][ctx.group.id]
    assert {:ok, []} = Ideation.list_groups(ctx.viewer, ctx.project.id, session_id)
    assert DateTime.compare(Repo.get!(Group, group_id).deleted_at, deleted.deleted_at) == :eq

    assert {:ok, restored} =
             Ideation.restore_group(ctx.facilitator, ctx.project.id, session_id, group_id, deleted.version, %{
               request_key: Ecto.UUID.generate(),
               deleted_at: deleted.deleted_at,
               idea_ids: [maps["ideas"][ctx.first.id], maps["ideas"][ctx.second.id]]
             })

    assert restored.id == group_id
    assert restored.version == deleted.version + 1
    assert restored.deleted_at == nil
    assert restored.synthesis == ctx.group.synthesis
    assert Enum.all?(restored.members, &(&1.source_revision == 1))
  end

  test "a missing group author resolves to nil without losing published provenance", ctx do
    capsule = capture(ctx)
    Repo.delete!(ctx.facilitator.user)
    Repo.delete_all(from(s in Session, where: s.project_id == ^ctx.project.id))
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [group]} = Ideation.list_groups(ctx.owner, ctx.project.id, session_id)
    assert group.author_id == nil
    assert group.synthesis == ctx.group.synthesis
    assert Enum.all?(Repo.all(Membership), &is_nil(&1.actor_id))
    assert Enum.all?(Repo.all(Revision), &is_nil(&1.actor_id))
    assert restore(ctx, capsule) == maps
  end

  test "version-three capsules normalize empty groups and preserve distinct retained generations", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 3)
      |> update_in(["rows"], &Map.drop(&1, ~w(groups group_memberships group_revisions)))

    assert {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["version"] == 4
    assert normalized["rows"]["groups"] == []
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert session_id != ctx.session.id
    assert {:ok, []} = Ideation.list_groups(ctx.owner, ctx.project.id, session_id)
    assert Repo.aggregate(Group, :count) == 1

    for _ <- 1..3, do: assert(restore(ctx, capsule) == maps)
    complete = capture(ctx)
    Repo.delete_all(from(s in Session, where: s.project_id == ^ctx.project.id))
    complete_maps = restore(ctx, complete)
    assert Repo.aggregate(Group, :count) == 1
    assert Repo.aggregate(Session, :count) == 2
    assert restore(ctx, complete) == complete_maps
  end

  test "authenticated invalid group sources and schema fields fail before replacement", ctx do
    private = idea_fixture(ctx)

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.first.id,
               1,
               edit_attrs(%{body: "<p>Unpublished second revision</p>"})
             )

    capsule = capture(ctx)
    {:ok, data} = Capsule.open(capsule)

    changes = [
      {"groups", "session_id", -1},
      {"groups", "author_id", "invalid"},
      {"groups", "version", 99},
      {"groups", "deleted_at", "2026-09-08T12:00:00.000000"},
      {"groups", "canvas", %{"x" => "left"}},
      {"groups", "canvas", %{"x" => 100, "y" => 60, "width" => 600, "height" => 400}},
      {"groups", "synthesis", Base.encode64("unreadable ciphertext")},
      {"group_memberships", "group_id", -1},
      {"group_memberships", "session_id", -1},
      {"group_memberships", "idea_id", private.id},
      {"group_memberships", "source_revision", 2},
      {"group_memberships", "removed_at", "invalid"},
      {"group_memberships", "removed_at", "2026-09-08T12:00:00.000000"},
      {"group_revisions", "group_id", -1},
      {"group_revisions", "session_id", -1},
      {"group_revisions", "number", 0},
      {"group_revisions", "operation", "publish"},
      {"group_revisions", "operation", "delete"},
      {"group_revisions", "request_key", Base.encode64("invalid")},
      {"group_revisions", "fingerprint", Base.encode64("invalid")},
      {"group_revisions", "idea_ids", [private.id]},
      {"group_revisions", "sources", %{to_string(ctx.first.id) => 2, to_string(ctx.second.id) => 1}},
      {"group_revisions", "sources", %{"not-an-id" => 1}}
    ]

    for {collection, field, value} <- changes do
      invalid = put_in(data, ["rows", collection, Access.at(0), field], value)
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(invalid))
    end

    duplicated =
      update_in(data, ["rows", "group_memberships"], fn [first | rest] ->
        copy = %{
          first
          | "id" => first["id"] + 1_000_000,
            "recovery_identity" => Base.encode64(:crypto.strong_rand_bytes(16))
        }

        [first, copy | rest]
      end)

    assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(duplicated))
    assert capture(ctx) == capsule
    assert {:ok, [group]} = Ideation.list_groups(ctx.owner, ctx.project.id, ctx.session.id)
    assert group.id == ctx.group.id
  end

  test "a session capsule stops at 500 live groups", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()
    [group] = data["rows"]["groups"]
    [revision] = data["rows"]["group_revisions"]

    padded = fn count ->
      groups = for i <- 1..count, do: %{group | "id" => 900_000 + i, "recovery_identity" => identity()}

      revisions =
        for i <- 1..count do
          %{
            revision
            | "id" => 900_000 + i,
              "group_id" => 900_000 + i,
              "recovery_identity" => identity(),
              "request_key" => identity(),
              "idea_ids" => [],
              "sources" => %{}
          }
        end

      data
      |> update_in(["rows", "groups"], &(&1 ++ groups))
      |> update_in(["rows", "group_revisions"], &(&1 ++ revisions))
    end

    assert GraphValidation.valid?(padded.(499)["rows"])
    refute GraphValidation.valid?(padded.(500)["rows"])
    assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(padded.(500)))
    assert {:ok, [only]} = Ideation.list_groups(ctx.owner, ctx.project.id, ctx.session.id)
    assert only.id == ctx.group.id
  end

  defp identity, do: Base.encode64(:crypto.strong_rand_bytes(16))

  defp group_attrs(ids) do
    %{
      request_key: Ecto.UUID.generate(),
      idea_ids: ids,
      title: "Shared theme",
      synthesis: "Two motives combine",
      canvas: %{x: 40, y: 60, width: 600, height: 400}
    }
  end

  defp capture(ctx) do
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok, ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
      end)

    snapshot["ideation"]
  end

  defp restore(ctx, capsule) do
    assert {:ok, maps} = restore_result(ctx, capsule)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    maps
  end

  defp restore_result(ctx, capsule) do
    Repo.transact(fn ->
      Repo.one!(from(p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE"))
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end

  defp authenticate(data) do
    {:ok, bytes} = data |> Jason.encode!() |> Vault.encrypt()
    %{"version" => 1, "ciphertext" => Base.encode64(bytes)}
  end
end
