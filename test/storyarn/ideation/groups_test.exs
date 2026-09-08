defmodule Storyarn.Ideation.GroupsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Groups.Membership
  alias Storyarn.Ideation.Groups.Revision

  setup do
    ctx = ideation_fixture()
    first = shared(ctx, 20, ctx.author)
    second = shared(ctx, 340, ctx.peer)
    Map.merge(ctx, %{first: first, second: second})
  end

  defp shared(ctx, x, actor) do
    idea_fixture(ctx, %{visibility: :shared, canvas: %{"x" => x, "y" => 100, "width" => 280, "color" => "mint"}}, actor)
  end

  defp attrs(ctx, extra \\ %{}) do
    Map.merge(
      %{
        request_key: Ecto.UUID.generate(),
        title: "Motivations",
        synthesis: "A shared synthesis",
        idea_ids: [ctx.first.id, ctx.second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      },
      extra
    )
  end

  defp create_group_fixture(ctx, extra \\ %{}) do
    {:ok, group} = Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, attrs(ctx, extra))
    group
  end

  defp edit_group(ctx, group, changes, actor \\ nil) do
    Ideation.update_group(
      actor || ctx.author,
      ctx.project.id,
      ctx.session.id,
      group.id,
      group.version,
      edit_attrs(changes)
    )
  end

  test "shared grouping retains source identities, authorship and pinned provenance", ctx do
    group = create_group_fixture(ctx)
    assert group.author_id == ctx.author.user.id
    assert group.version == 1
    assert group.idea_ids == [ctx.first.id, ctx.second.id]
    assert Enum.all?(group.members, &(&1.source_revision == 1))
    assert Enum.all?(group.members, &(Enum.sort(Map.keys(&1)) == [:canvas, :idea_id, :source_revision]))
    assert Repo.aggregate(Revision, :count) == 1
    assert %{actor_id: actor_id, sources: sources} = Repo.get_by!(Revision, group_id: group.id, number: 1)
    assert actor_id == ctx.author.user.id
    assert sources == %{to_string(ctx.first.id) => 1, to_string(ctx.second.id) => 1}
    assert {:ok, first} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id)
    assert first.author_id == ctx.first.author_id
    assert first.body == ctx.first.body
    assert first.revision == 1
    assert {:ok, [read]} = Ideation.list_groups(ctx.viewer, ctx.project.id, ctx.session.id)
    assert read == group
  end

  test "draft, foreign, duplicate and already grouped sources are rejected", ctx do
    private = idea_fixture(ctx)

    for ids <- [[ctx.first.id], [ctx.first.id, ctx.first.id], [ctx.first.id, private.id], [ctx.first.id, 9_999_999]] do
      assert {:error, :invalid_group_members} =
               Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, attrs(ctx, %{idea_ids: ids}))
    end

    create_group_fixture(ctx)
    assert {:error, :already_grouped} = Ideation.create_group(ctx.peer, ctx.project.id, ctx.session.id, attrs(ctx))
    assert Repo.aggregate(Group, :count) == 1
  end

  test "editors update synthesis and ungroup without overwriting the source notes", ctx do
    group = create_group_fixture(ctx)
    assert {:ok, updated} = edit_group(ctx, group, %{synthesis: "Reframed by another editor", idea_ids: []}, ctx.peer)
    assert updated.idea_ids == []
    assert updated.synthesis == "Reframed by another editor"
    assert updated.author_id == group.author_id
    assert Repo.get_by!(Revision, group_id: group.id, number: 2).actor_id == ctx.peer.user.id
    assert Repo.aggregate(Membership, :count) == 2
    assert Enum.all?(Repo.all(Membership), & &1.removed_at)
    assert {:ok, restored} = edit_group(ctx, updated, %{idea_ids: group.idea_ids})
    assert restored.idea_ids == group.idea_ids
    assert restored.synthesis == updated.synthesis
    assert Repo.aggregate(Membership, :count) == 4
  end

  test "separating synthesis preserves its position and undo restores the original anchor atomically", ctx do
    group = create_group_fixture(ctx)
    assert {:ok, standalone} = edit_group(ctx, group, %{idea_ids: [], canvas: %{x: 680, y: 100}})
    assert standalone.canvas == %{"x" => 680, "y" => 100, "width" => 650, "height" => 450}
    assert standalone.idea_ids == []
    assert {:ok, source} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id)
    assert source.canvas["x"] == 20
    assert source.canvas["version"] == nil

    assert {:ok, restored} = edit_group(ctx, standalone, %{idea_ids: group.idea_ids, canvas: %{x: 0, y: 0}})
    assert restored.canvas == group.canvas
    assert restored.idea_ids == group.idea_ids
    assert {:error, :invalid_canvas} = edit_group(ctx, restored, %{canvas: %{x: 1, y: 2}})
    assert {:error, :invalid_canvas} = edit_group(ctx, restored, %{idea_ids: group.idea_ids, canvas: %{x: 1, y: 2}})
  end

  test "undo detachment retains the original published source pin after the note receives a new revision", ctx do
    group = create_group_fixture(ctx)
    assert {:ok, standalone} = edit_group(ctx, group, %{idea_ids: []})

    assert {:ok, note} =
             Ideation.update_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.first.id,
               1,
               edit_attrs(%{body: "<p>A changed source</p>"})
             )

    assert note.published_revision == 2
    assert {:ok, restored} = edit_group(ctx, standalone, %{idea_ids: group.idea_ids})
    assert Enum.all?(restored.members, &(&1.source_revision == 1))
    revision = Repo.get_by!(Revision, group_id: group.id, number: 3)
    assert revision.sources[to_string(ctx.first.id)] == 1
    assert restored.synthesis == group.synthesis
  end

  test "group writes require current editing access and an open session", ctx do
    group = create_group_fixture(ctx)
    assert {:error, :unauthorized} = edit_group(ctx, group, %{title: "Denied"}, ctx.viewer)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision)
    assert {:error, :session_archived} = edit_group(ctx, group, %{title: "Denied"})
    assert {:ok, [_]} = Ideation.list_groups(ctx.author, ctx.project.id, ctx.session.id)
  end

  test "private mode hides all derived text and prevents mutations even for the author", ctx do
    group = create_group_fixture(ctx)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    for actor <- [ctx.author, ctx.peer, ctx.facilitator, ctx.viewer] do
      assert {:ok, []} = Ideation.list_groups(actor, ctx.project.id, ctx.session.id)
    end

    assert {:error, :private_mode} = edit_group(ctx, group, %{title: "Hidden"})
    assert {:error, :private_mode} = Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, attrs(ctx))
  end

  test "UUID receipts remain durable through later edits and cannot be reused for different intent", ctx do
    request = attrs(ctx)
    assert {:ok, group} = Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, request)
    assert {:ok, later} = edit_group(ctx, group, %{title: "Latest"})
    assert later.version == 2
    assert {:error, :stale_group} = Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, request)
    assert Repo.aggregate(Revision, :count) == 2

    assert {:error, :idempotency_conflict} =
             Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{request | title: "Different"})

    assert {:error, :stale_group} = edit_group(ctx, group, %{title: "Old"})
  end

  test "atomic group movement rejects any stale source without moving other members", ctx do
    group = create_group_fixture(ctx)

    assert {:ok, _} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id, 0, %{
               "x" => 75,
               "y" => 100,
               "request_key" => Ecto.UUID.generate()
             })

    move = %{
      request_key: Ecto.UUID.generate(),
      x: 100,
      y: 200,
      member_versions: [%{id: ctx.first.id, version: 0}, %{id: ctx.second.id, version: 0}]
    }

    assert {:error, :stale_canvas} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, move)
    assert Repo.get!(Group, group.id).canvas["x"] == 0
    assert Repo.aggregate(Revision, :count) == 1
    assert {:ok, second} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, ctx.second.id)
    assert second.canvas["x"] == 340
    move = %{move | member_versions: [%{id: ctx.first.id, version: 1}, %{id: ctx.second.id, version: 0}]}
    assert {:ok, moved} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, move)
    assert moved.canvas["x"] == 100
    assert Enum.map(moved.members, & &1.canvas["x"]) == [175, 440]
    assert Enum.map(moved.members, & &1.canvas["y"]) == [300, 300]
    assert {:ok, ^moved} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, move)
    assert {:ok, second} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, ctx.second.id)
    assert second.revision == 1
  end

  test "move retry rejects a later independent note move even when group version is unchanged", ctx do
    group = create_group_fixture(ctx)

    move = %{
      request_key: Ecto.UUID.generate(),
      x: 20,
      y: 30,
      member_versions: [%{id: ctx.first.id, version: 0}, %{id: ctx.second.id, version: 0}]
    }

    assert {:ok, _} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, move)

    assert {:ok, _} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id, 1, %{
               "x" => 300,
               "y" => 400,
               "request_key" => Ecto.UUID.generate()
             })

    assert {:error, :stale_canvas} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, move)
    assert Repo.aggregate(Revision, :count) == 2
  end

  test "deleted notes leave retained provenance but cannot strand moving or reading a group", ctx do
    group = create_group_fixture(ctx)
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id, 1)
    assert {:ok, [visible]} = Ideation.list_groups(ctx.peer, ctx.project.id, ctx.session.id)
    assert visible.idea_ids == [ctx.second.id]
    assert visible.synthesis == group.synthesis
    move = %{request_key: Ecto.UUID.generate(), x: 10, y: 10, member_versions: [%{id: ctx.second.id, version: 0}]}
    assert {:ok, moved} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, move)
    assert moved.idea_ids == [ctx.second.id]
    assert Repo.get_by!(Revision, group_id: group.id, number: 2).idea_ids == group.idea_ids
    assert Repo.aggregate(Membership, :count) == 2
  end

  test "delete preserves ideas and only the deleting actor can restore the exact deletion", ctx do
    group = create_group_fixture(ctx)

    assert {:ok, deleted} =
             Ideation.delete_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 1, Ecto.UUID.generate())

    assert {:ok, []} = Ideation.list_groups(ctx.author, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id)
    restore = %{request_key: Ecto.UUID.generate(), deleted_at: deleted.deleted_at, idea_ids: group.idea_ids}

    assert {:error, :stale_group} =
             Ideation.restore_group(ctx.author, ctx.project.id, ctx.session.id, group.id, 2, restore)

    assert {:ok, restored} = Ideation.restore_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 2, restore)
    assert restored.version == 3
    assert restored.idea_ids == group.idea_ids
    assert restored.synthesis == group.synthesis
    assert {:ok, ^restored} = Ideation.restore_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 2, restore)

    assert {:error, :not_found} =
             Ideation.restore_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, 3, %{
               restore
               | request_key: Ecto.UUID.generate()
             })
  end

  test "undo cannot steal sources joined to another group in the meantime", ctx do
    group = create_group_fixture(ctx)

    assert {:ok, deleted} =
             Ideation.delete_group(ctx.author, ctx.project.id, ctx.session.id, group.id, 1, Ecto.UUID.generate())

    create_group_fixture(ctx)
    restore = %{request_key: Ecto.UUID.generate(), deleted_at: deleted.deleted_at, idea_ids: group.idea_ids}

    assert {:error, :already_grouped} =
             Ideation.restore_group(ctx.author, ctx.project.id, ctx.session.id, group.id, 2, restore)

    assert Repo.get!(Group, group.id).deleted_at
  end

  test "notifications contain only invalidation and are emitted only after a successful commit", ctx do
    assert :ok = Ideation.subscribe_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    group = create_group_fixture(ctx)
    session_id = ctx.session.id
    assert_receive {:ideation_changed, ^session_id}
    assert {:error, :invalid_group_members} = edit_group(ctx, group, %{idea_ids: [9_999_999]})
    refute_receive {:ideation_changed, ^session_id}

    assert {:error, :group_requires_outer_transaction} =
             Repo.transact(fn ->
               assert {:error, :group_requires_outer_transaction} = edit_group(ctx, group, %{title: "Outer"})
             end)

    refute_receive {:ideation_changed, ^session_id}
  end
end
