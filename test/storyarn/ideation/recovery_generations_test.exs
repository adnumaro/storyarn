defmodule Storyarn.Ideation.RecoveryGenerationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Project

  setup do
    ctx = ideation_fixture()
    Map.put(ctx, :idea, idea_fixture(ctx))
  end

  test "repeated restores reuse identical generations, including history in a subsequent capture", ctx do
    first = capture(ctx)
    original_counts = counts(ctx)
    for _ <- 1..3, do: assert(restore(ctx, first)["sessions"][ctx.session.id] == ctx.session.id)
    assert counts(ctx) == original_counts

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.idea.id,
               1,
               edit_attrs(%{body: "<p>A distinct generation</p>"})
             )

    maps = restore(ctx, first)
    refute maps["sessions"][ctx.session.id] == ctx.session.id
    retained_counts = counts(ctx)
    assert retained_counts["sessions"] == 2

    for _ <- 1..3 do
      complete = capture(ctx)
      restore(ctx, complete)
      assert counts(ctx) == retained_counts
      restore(ctx, first)
      assert counts(ctx) == retained_counts
    end

    complete = capture(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    restore(ctx, complete)
    assert counts(ctx) == retained_counts
    assert {:ok, [previous]} = Ideation.list_sessions(ctx.owner, ctx.project.id, status: :replaced)
    assert {:ok, recovered} = Ideation.recover_session(ctx.owner, ctx.project.id, previous.id, previous.revision)

    assert {:ok, [%{body: "<p>A distinct generation</p>"}]} =
             Ideation.list_ideas(ctx.author, ctx.project.id, recovered.id)

    assert {:ok, []} = Ideation.list_ideas(ctx.owner, ctx.project.id, recovered.id)
  end

  test "format 2 can restore over retained history, but not over a live or archived session", ctx do
    assert restore_result(ctx, nil) == {:error, :legacy_snapshot_excludes_ideation}
    assert {:ok, archived} = Ideation.archive_session(ctx.owner, ctx.project.id, ctx.session.id, ctx.session.revision)
    assert restore_result(ctx, nil) == {:error, :legacy_snapshot_excludes_ideation}

    Repo.update_all(from(s in Session, where: s.id == ^archived.id), set: [deleted_at: ~U[2026-09-07 12:00:00.000000Z]])
    before = counts(ctx)
    assert restore_result(ctx, nil) == {:ok, %{}}
    assert counts(ctx) == before
    assert {:ok, [_]} = Ideation.list_sessions(ctx.owner, ctx.project.id, status: :replaced)
  end

  test "only the owner can explicitly purge a replaced generation, and retained archives still recover it", ctx do
    assert {:error, :session_not_replaced} =
             Ideation.purge_replaced_session(ctx.owner, ctx.project.id, ctx.session.id, ctx.session.revision)

    first = capture(ctx)
    assert {:ok, updated} = Ideation.update_session(ctx.owner, ctx.project.id, ctx.session.id, 1, %{title: "Retained"})
    restore(ctx, first)
    retained = capture(ctx)

    assert {:error, :unauthorized} =
             Ideation.purge_replaced_session(ctx.facilitator, ctx.project.id, updated.id, updated.revision)

    assert {:error, :stale_revision} = Ideation.purge_replaced_session(ctx.owner, ctx.project.id, updated.id, 1)
    assert {:ok, :purged} = Ideation.purge_replaced_session(ctx.owner, ctx.project.id, updated.id, updated.revision)

    assert {:error, :not_found} =
             Ideation.purge_replaced_session(ctx.owner, ctx.project.id, updated.id, updated.revision)

    assert {:ok, []} = Ideation.list_sessions(ctx.owner, ctx.project.id, status: :replaced)

    restore(ctx, retained)
    assert {:ok, [%{title: "Retained"}]} = Ideation.list_sessions(ctx.owner, ctx.project.id, status: :replaced)
  end

  test "authenticated broken foreign keys are rejected before replacement", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()

    mutations = [
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "session_id"], -1) end,
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "source_idea_id"], -1) end,
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "revision"], 999) end,
      fn data -> put_in(data, ["rows", "revisions", Access.at(0), "idea_id"], -1) end,
      fn data -> put_in(data, ["rows", "edits", Access.at(0), "result_revision"], 999) end
    ]

    before = counts(ctx)

    for mutate <- mutations do
      {:ok, bytes} = data |> mutate.() |> Jason.encode!() |> Vault.encrypt()
      invalid = %{"version" => 1, "ciphertext" => Base.encode64(bytes)}
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, invalid)
      assert counts(ctx) == before
      assert {:ok, _} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)
    end
  end

  defp capture(ctx) do
    {:ok, capsule} =
      Repo.transact(fn ->
        lock(ctx)
        Ideation.capture_recovery(ctx.project.id)
      end)

    capsule
  end

  defp restore(ctx, capsule) do
    {:ok, maps} = restore_result(ctx, capsule)
    maps
  end

  defp restore_result(ctx, capsule) do
    Repo.transact(fn ->
      lock(ctx)
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end

  defp lock(ctx), do: Repo.one!(from p in Project, where: p.id == ^ctx.project.id, lock: "FOR UPDATE")

  defp counts(ctx) do
    {:ok, data} = ctx |> capture() |> Capsule.open()
    Map.new(Inventory.tables(), fn {collection, _, _, _} -> {collection, length(data["rows"][collection])} end)
  end
end
