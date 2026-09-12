defmodule Storyarn.Ideation.ReferencesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Revision
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Sheets

  setup do
    ctx = ideation_fixture()
    Map.put(ctx, :sheet, sheet_fixture(ctx.project, %{name: "Pilot", description: "Original overview"}))
  end

  defp attrs(ctx, extra \\ %{}),
    do:
      Map.merge(
        %{target_type: "sheet", target_id: ctx.sheet.id, relation: "origin", request_key: Ecto.UUID.generate()},
        extra
      )

  defp add(ctx, idea_id \\ nil),
    do: Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, idea_id, attrs(ctx))

  defp list(ctx, scope \\ nil, idea_id \\ nil),
    do: Ideation.list_references(scope || ctx.author, ctx.project.id, ctx.session.id, idea_id)

  test "explicit shared links retain a consulted overview without changing the target", ctx do
    before = Repo.get!(Sheets.Sheet, ctx.sheet.id)
    {:ok, reference} = add(ctx)
    assert reference.base["name"] == "Pilot"
    assert reference.base["overview"]["comparison_scope"] == "overview_v1"
    assert reference.status == "current"
    assert reference.version == 1
    assert Repo.get!(Sheets.Sheet, ctx.sheet.id) == before
    assert {:ok, %{references: [^reference], next_cursor: nil}} = list(ctx, ctx.viewer)

    assert {:ok, %{references: [%{session_id: id}], next_cursor: nil}} =
             Ideation.list_reference_backlinks(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id)

    assert id == ctx.session.id
  end

  test "retries are actor-scoped and cannot retarget a pending request", ctx do
    attrs = attrs(ctx)
    {:ok, first} = Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, attrs)
    assert {:ok, ^first} = Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, attrs)

    assert {:error, :idempotency_conflict} =
             Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, %{attrs | relation: "affects"})

    assert {:error, :reference_exists} = add(ctx)
    assert Repo.aggregate(Reference, :count) == 1
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "current changes never rewrite the consulted context; refresh is explicit and versioned", ctx do
    {:ok, first} = add(ctx)
    assert {:ok, _} = Sheets.update_sheet(ctx.sheet, %{name: "Revised pilot"})
    assert {:ok, %{references: [changed]}} = list(ctx)
    assert changed.status == "changed"
    assert changed.base == first.base
    assert changed.current.name == "Revised pilot"
    key = Ecto.UUID.generate()

    assert {:ok, refreshed} =
             Ideation.refresh_reference(ctx.peer, ctx.project.id, ctx.session.id, nil, first.id, 1, key)

    assert refreshed.status == "current"
    assert refreshed.version == 2

    assert {:ok, ^refreshed} =
             Ideation.refresh_reference(ctx.peer, ctx.project.id, ctx.session.id, nil, first.id, 1, key)

    assert {:error, :stale_reference} =
             Ideation.refresh_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               first.id,
               1,
               Ecto.UUID.generate()
             )

    assert {:ok, [latest, original]} =
             Ideation.reference_history(ctx.viewer, ctx.project.id, ctx.session.id, nil, first.id)

    assert original.context == first.base
    assert latest.context == refreshed.base
  end

  test "deleted or generation-mismatched targets hide all saved context", ctx do
    {:ok, first} = add(ctx)
    assert {:ok, deleted} = Sheets.delete_sheet(ctx.author, ctx.sheet)
    assert {:ok, %{references: [hidden]}} = list(ctx)
    assert %{status: "unavailable", base: nil, current: nil, target_id: nil, captured_at: nil} = hidden
    assert {:error, :not_found} = Ideation.reference_history(ctx.author, ctx.project.id, ctx.session.id, nil, first.id)
    assert {:ok, _} = Sheets.restore_sheet(deleted)
    assert {:ok, %{references: [%{status: "current"}]}} = list(ctx)

    Repo.update_all(from(r in Reference, where: r.id == ^first.id),
      set: [target_identity: "created:2000-01-01T00:00:00Z"]
    )

    assert {:ok, %{references: [%{status: "unavailable", base: nil}]}} = list(ctx)
  end

  test "detached recovery destinations remain visible as unavailable without breaking the page", ctx do
    {:ok, first} = add(ctx)
    Repo.update_all(from(r in Reference, where: r.id == ^first.id), set: [target_id: nil])
    assert {:ok, %{references: [%{status: "unavailable", base: nil}], next_cursor: nil}} = list(ctx)
  end

  test "private ideas hide inverse links while preserving their stored identity", ctx do
    private = idea_fixture(ctx)
    assert {:error, :not_found} = add(ctx, private.id)
    shared = idea_fixture(ctx, %{visibility: :shared})
    {:ok, reference} = add(ctx, shared.id)
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, session.id, session.revision, true)
    assert {:error, :not_found} = list(ctx, ctx.author, shared.id)

    assert {:ok, %{references: []}} =
             Ideation.list_reference_backlinks(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id)

    assert Repo.get!(Reference, reference.id)
  end

  test "viewers cannot write, foreign targets cannot be linked, and revoked members cannot read", ctx do
    assert {:error, _} = Ideation.add_reference(ctx.viewer, ctx.project.id, ctx.session.id, nil, attrs(ctx))
    foreign = sheet_fixture()

    assert {:error, :not_found} =
             Ideation.add_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               attrs(ctx, %{target_id: foreign.id})
             )

    {:ok, reference} = add(ctx)
    assert {:error, _} = list(ctx, user_scope_fixture())

    Repo.delete_all(
      from m in ProjectMembership, where: m.project_id == ^ctx.project.id and m.user_id == ^ctx.author.user.id
    )

    assert {:error, _} = list(ctx)
    assert {:error, _} = Ideation.reference_history(ctx.author, ctx.project.id, ctx.session.id, nil, reference.id)
  end

  test "removing a reference leaves its target and history intact and is retryable", ctx do
    {:ok, reference} = add(ctx)
    key = Ecto.UUID.generate()

    assert {:ok, removed} =
             Ideation.remove_reference(ctx.peer, ctx.project.id, ctx.session.id, nil, reference.id, 1, key)

    assert {:ok, ^removed} =
             Ideation.remove_reference(ctx.peer, ctx.project.id, ctx.session.id, nil, reference.id, 1, key)

    assert {:ok, %{references: []}} = list(ctx)
    assert Repo.get!(Sheets.Sheet, ctx.sheet.id).deleted_at == nil
    assert Repo.aggregate(Revision, :count) == 2
  end

  test "pagination is bounded and source selection is explicit", ctx do
    for relation <- ~w(origin reference affects result work),
        do:
          assert(
            {:ok, _} =
              Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, attrs(ctx, %{relation: relation}))
          )

    assert {:ok, %{references: rows, next_cursor: cursor}} =
             Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil, limit: 2)

    assert length(rows) == 2

    assert {:ok, %{references: next}} =
             Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil, limit: 2, before_id: cursor)

    refute Enum.any?(next, &(&1.id in Enum.map(rows, fn row -> row.id end)))

    assert {:error, :invalid_pagination} =
             Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil, limit: 500)
  end

  test "backlink revalidation does not promote the lookahead and repeat it on the next page", ctx do
    references =
      for relation <- ~w(origin reference affects) do
        {:ok, reference} =
          Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, attrs(ctx, %{relation: relation}))

        reference
      end

    [lookahead, boundary, newest] = references
    marker = make_ref()
    Process.put(marker, true)

    :ok =
      :telemetry.attach(
        marker,
        [:storyarn, :repo, :query],
        &unlink_during_backlinks/4,
        {self(), marker, newest.id}
      )

    try do
      assert {:ok, %{references: [remaining], next_cursor: cursor}} =
               Ideation.list_reference_backlinks(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id, limit: 2)

      assert remaining.id == boundary.id
      assert cursor == boundary.id
      refute Process.get(marker), "the first query must lose a row before revalidation"

      assert {:ok, %{references: [last], next_cursor: nil}} =
               Ideation.list_reference_backlinks(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id,
                 limit: 2,
                 before_id: cursor
               )

      assert last.id == lookahead.id
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp unlink_during_backlinks(_event, _measurements, %{query: query}, {pid, marker, reference_id}) do
    if self() == pid and String.contains?(query, ~s(FROM "ideation_references")) and Process.delete(marker) do
      Repo.update_all(from(r in Reference, where: r.id == ^reference_id),
        set: [deleted_at: Storyarn.Platform.Shared.TimeHelpers.now()]
      )
    end
  end
end
