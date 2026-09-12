defmodule Storyarn.Ideation.ContextualSessionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Revision
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Sheets

  setup do
    ctx = ideation_fixture()
    Map.put(ctx, :sheet, sheet_fixture(ctx.project, %{name: "Pilot", description: "Original overview"}))
  end

  test "creation captures whole Sheet Flow and Scene context and retries never duplicate a session", ctx do
    targets = [{"sheet", ctx.sheet}, {"flow", flow_fixture(ctx.project)}, {"scene", scene_fixture(ctx.project)}]

    for {type, target} <- targets do
      attrs = attrs(ctx, type, target.id)
      assert {:ok, result} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
      assert result.reference.relation == "origin"
      assert result.reference.base["overview"]["comparison_scope"] == "overview_v1"
      assert result.reference.current.id == target.id
      assert result.session.title == "Explore alternatives"
      assert {:ok, ^result} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)

      assert {:error, :idempotency_conflict} =
               Ideation.create_contextual_session(ctx.author, ctx.project.id, %{attrs | title: "Different request"})

      assert {:ok, %{linked_sessions: [linked]}} =
               Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, type, target.id)

      assert linked.id == result.session.id

      assert {:ok, ^result} =
               Ideation.resume_contextual_session(ctx.viewer, ctx.project.id, type, target.id, result.session.id)
    end

    assert Repo.aggregate(Session, :count) == 4
    assert Repo.aggregate(Reference, :count) == 3
    assert Repo.aggregate(Revision, :count) == 3
  end

  test "failed session validation and stale or unavailable context leave no orphan session", ctx do
    attrs = attrs(ctx)

    assert {:error, %Ecto.Changeset{}} =
             Ideation.create_contextual_session(ctx.author, ctx.project.id, %{attrs | title: ""})

    assert {:ok, sheet} = Sheets.update_sheet(ctx.sheet, %{name: "Revised pilot"})
    assert {:error, :stale_context} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)

    assert {:error, :stale_context} =
             Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:ok, _} = Sheets.delete_sheet(ctx.author, sheet)
    assert {:error, :not_found} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert Repo.aggregate(Session, :count) == 1
    assert Repo.aggregate(Reference, :count) == 0
  end

  test "a committed retry preserves consulted history after changes and refuses an unavailable origin", ctx do
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert {:ok, sheet} = Sheets.update_sheet(ctx.sheet, %{description: "New overview"})
    assert {:ok, retried} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert retried.session.id == first.session.id
    assert retried.reference.base == first.reference.base
    assert retried.reference.status == "changed"
    assert {:ok, _} = Sheets.delete_sheet(ctx.author, sheet)
    assert {:error, :not_found} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)

    assert {:ok, %{status: "unavailable", base: nil, current: nil, target_id: nil}} =
             Ideation.get_reference(ctx.viewer, ctx.project.id, first.session.id, nil, first.reference.id)

    assert Repo.aggregate(Session, :count) == 2
  end

  test "linking retains existing provenance and excludes linked sessions from choices", ctx do
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert {:ok, ^first} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:ok, reused} =
             Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, %{
               attrs
               | request_key: Ecto.UUID.generate()
             })

    assert reused.reference == first.reference

    assert {:ok, %{linked_sessions: [linked], available_sessions: []}} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id)

    assert linked.id == ctx.session.id
    assert Repo.aggregate(Reference, :count) == 1
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "existing reference relations are reused without silently turning them into an origin", ctx do
    attrs = attrs(ctx)

    assert {:ok, reference} =
             Ideation.add_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               Map.put(attrs, :relation, "affects")
             )

    assert {:ok, result} =
             Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, %{
               attrs
               | request_key: Ecto.UUID.generate()
             })

    assert result.reference == reference
    assert result.reference.relation == "affects"
    assert Repo.aggregate(Reference, :count) == 1
  end

  test "archived sessions remain resumable but cannot receive new contextual links", ctx do
    attrs = attrs(ctx)
    assert {:ok, _} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 1)

    assert {:ok, %{linked_sessions: [%{status: :archived}], available_sessions: []}} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id)

    assert {:ok, _} =
             Ideation.resume_contextual_session(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id, ctx.session.id)

    assert {:error, :session_archived} =
             Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)
  end

  test "viewer access is read-only and foreign or revoked access cannot create or resume", ctx do
    attrs = attrs(ctx)
    assert {:error, _} = Ideation.create_contextual_session(ctx.viewer, ctx.project.id, attrs)
    assert {:error, _} = Ideation.link_contextual_session(ctx.viewer, ctx.project.id, ctx.session.id, attrs)

    assert {:error, :not_found} =
             Ideation.resume_contextual_session(ctx.author, ctx.project.id, "sheet", ctx.sheet.id, ctx.session.id)

    foreign = sheet_fixture()

    assert {:error, :not_found} =
             Ideation.get_contextual_brainstorming(ctx.author, ctx.project.id, "sheet", foreign.id)

    assert {:ok, result} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)

    Repo.delete_all(
      from(m in ProjectMembership, where: m.project_id == ^ctx.project.id and m.user_id == ^ctx.author.user.id)
    )

    assert {:error, _} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert {:error, _} = Ideation.get_contextual_brainstorming(ctx.author, ctx.project.id, "sheet", ctx.sheet.id)

    assert {:error, :not_found} =
             Ideation.resume_contextual_session(ctx.author, ctx.project.id, "sheet", ctx.sheet.id, result.session.id)

    assert {:error, _} =
             Ideation.get_contextual_brainstorming(user_scope_fixture(), ctx.project.id, "sheet", ctx.sheet.id)
  end

  test "context lists only whole-session links and paginates unique sessions", ctx do
    attrs = attrs(ctx)
    published = idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, _} = Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, published.id, attrs)

    assert {:ok, %{linked_sessions: [], available_sessions: [%{id: id}]}} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id)

    assert id == ctx.session.id

    sessions =
      for _ <- 1..3 do
        assert {:ok, result} =
                 Ideation.create_contextual_session(ctx.author, ctx.project.id, %{
                   attrs
                   | request_key: Ecto.UUID.generate()
                 })

        result.session
      end

    assert {:ok, %{linked_sessions: first, linked_next_cursor: cursor}} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id, limit: 2)

    assert length(first) == 2

    assert {:ok, %{linked_sessions: [last], linked_next_cursor: nil}} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id,
               limit: 2,
               linked_before_id: cursor
             )

    assert last.id == hd(sessions).id

    assert {:error, :invalid_pagination} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id, limit: 51)
  end

  test "generation replacement prevents a pending command from binding the numeric id", ctx do
    attrs = attrs(ctx)
    Repo.update_all(from(s in Sheets.Sheet, where: s.id == ^ctx.sheet.id), set: [inserted_at: ~U[2000-01-01 00:00:00Z]])
    assert {:error, :not_found} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert {:error, :not_found} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert Repo.aggregate(Session, :count) == 1
  end

  test "contextual origins and creation receipts survive sealed recovery", ctx do
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)

    assert {:ok, capsule} =
             Repo.transact(fn ->
               Repo.one!(from(p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE"))
               Ideation.capture_recovery(ctx.project.id)
             end)

    Repo.delete_all(from(s in Session, where: s.project_id == ^ctx.project.id))

    assert {:ok, maps} =
             Repo.transact(fn ->
               Repo.one!(from(p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE"))
               Ideation.restore_recovery(ctx.project.id, capsule)
             end)

    restored_id = maps["sessions"][first.session.id]
    assert restored_id != first.session.id
    assert {:ok, retried} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert retried.session.id == restored_id
    assert retried.reference.base == first.reference.base

    assert {:ok, ^retried} =
             Ideation.resume_contextual_session(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id, restored_id)

    assert Repo.aggregate(Session, :count) == 2
  end

  test "retrying a reused reference never recreates a later unlink", ctx do
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)
    reused_attrs = %{attrs | request_key: Ecto.UUID.generate()}
    assert {:ok, reused} = Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, reused_attrs)
    assert reused.reference == first.reference
    assert {:ok, ^reused} = Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, reused_attrs)

    assert {:ok, _} =
             Ideation.remove_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               first.reference.id,
               first.reference.version,
               Ecto.UUID.generate()
             )

    assert {:error, :not_found} =
             Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, reused_attrs)

    assert Repo.aggregate(Reference, :count) == 1
    assert {:ok, %{references: []}} = Ideation.list_references(ctx.peer, ctx.project.id, ctx.session.id, nil)
  end

  test "a replaced creation receipt fences retries after restoring an earlier snapshot", ctx do
    capsule = capture_context(ctx)
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    restore_context(ctx, capsule)
    assert Repo.get!(Session, first.session.id).deleted_at
    count = Repo.aggregate(Session, :count)

    assert {:error, :not_found} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert Repo.aggregate(Session, :count) == count
    assert {:error, :not_found} = Ideation.get_session(ctx.author, ctx.project.id, first.session.id)

    assert {:ok, %{linked_sessions: []}} =
             Ideation.get_contextual_brainstorming(ctx.viewer, ctx.project.id, "sheet", ctx.sheet.id)
  end

  test "reused-link receipts survive recovery and remain fenced after unlink", ctx do
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)
    reused_attrs = %{attrs | request_key: Ecto.UUID.generate()}
    assert {:ok, _} = Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, reused_attrs)
    capsule = capture_context(ctx)
    maps = restore_context(ctx, capsule)
    assert maps["sessions"][ctx.session.id] == ctx.session.id
    assert {:ok, _} = Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, reused_attrs)

    assert {:ok, _} =
             Ideation.remove_reference(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               nil,
               first.reference.id,
               first.reference.version,
               Ecto.UUID.generate()
             )

    assert {:error, :not_found} =
             Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, reused_attrs)
  end

  test "creation replay prefers the restored active receipt over a replaced generation", ctx do
    attrs = attrs(ctx)
    assert {:ok, first} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    capsule = capture_context(ctx)
    assert {:ok, _} = Ideation.update_session(ctx.author, ctx.project.id, first.session.id, 1, %{title: "Later title"})
    maps = restore_context(ctx, capsule)
    restored_id = maps["sessions"][first.session.id]
    assert restored_id != first.session.id
    assert {:ok, retried} = Ideation.create_contextual_session(ctx.author, ctx.project.id, attrs)
    assert retried.session.id == restored_id
    assert retried.session.title == "Explore alternatives"
  end

  test "recovery rejects malformed or foreign reused-link receipt identities", ctx do
    attrs = attrs(ctx)
    assert {:ok, _} = Ideation.link_contextual_session(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:ok, _} =
             Ideation.link_contextual_session(ctx.peer, ctx.project.id, ctx.session.id, %{
               attrs
               | request_key: Ecto.UUID.generate()
             })

    assert {:ok, data} = ctx |> capture_context() |> Capsule.open()

    for {key, value} <- [{"key", "invalid"}, {"fingerprint", "invalid"}, {"reference_identity", Ecto.UUID.generate()}] do
      invalid =
        update_in(data, ["rows", "session_revisions"], fn revisions ->
          Enum.map(revisions, fn revision ->
            if revision["action"] == "context_linked",
              do: put_in(revision, ["snapshot", "contextual_request", key], value),
              else: revision
          end)
        end)

      assert {:error, :ideation_recovery_capture_failed} = Capsule.seal(invalid)
    end
  end

  defp capture_context(ctx) do
    assert {:ok, capsule} =
             Repo.transact(fn ->
               Repo.one!(from(p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE"))
               Ideation.capture_recovery(ctx.project.id)
             end)

    capsule
  end

  defp restore_context(ctx, capsule) do
    assert {:ok, maps} =
             Repo.transact(fn ->
               Repo.one!(from(p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE"))
               Ideation.restore_recovery(ctx.project.id, capsule)
             end)

    maps
  end

  defp attrs(ctx, type \\ "sheet", id \\ nil) do
    assert {:ok, %{target: target}} =
             Ideation.get_contextual_brainstorming(ctx.author, ctx.project.id, type, id || ctx.sheet.id)

    %{
      title: "Explore alternatives",
      target_type: type,
      target_id: target.id,
      target_identity: target.identity,
      target_fingerprint: target.fingerprint,
      request_key: Ecto.UUID.generate()
    }
  end
end
