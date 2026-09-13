defmodule Storyarn.Ideation.DecisionRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.GraphValidation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    ctx = ideation_fixture()
    first = idea_fixture(ctx, %{visibility: :shared, title: "A published motive", body: "<p>The hero stays.</p>"})
    second = idea_fixture(ctx, %{visibility: :shared, title: "Another motive"})

    {:ok, group} =
      Ideation.create_group(ctx.facilitator, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        idea_ids: [first.id, second.id],
        title: "Shared motives",
        synthesis: "The hero chooses the village.",
        canvas: %{x: 40, y: 60, width: 600, height: 400}
      })

    ctx = Map.merge(ctx, %{first: first, second: second, group: group})
    attrs = proposal_attrs(ctx, [%{type: "idea", id: first.id}, %{type: "group", id: group.id}])
    {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    Map.merge(ctx, %{decision: decision, proposal_attrs: attrs})
  end

  test "physical recovery retains a previous agreement, pending revision, sources and retry receipts", ctx do
    accept_key = Ecto.UUID.generate()
    assert {:ok, accepted} = accept(ctx, ctx.decision.id, 1, accept_key)
    attrs = Map.merge(ctx.proposal_attrs, %{request_key: Ecto.UUID.generate(), conclusion: "The hero leaves later."})

    assert {:ok, revised} =
             Ideation.revise_decision(ctx.author, ctx.project.id, ctx.session.id, accepted.id, 2, attrs)

    assert revised.version == 3
    before = revisions(ctx.decision.id)
    assert Enum.map(before, & &1.operation) == ~w(propose accept revise)
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.second.id, 1)
    capsule = capture(ctx)
    assert {:ok, %{"version" => 6, "rows" => rows}} = Capsule.open(capsule)
    assert length(rows["decisions"]) == 1
    assert length(rows["decision_revisions"]) == 3
    refute Jason.encode!(rows) =~ "The hero leaves later"
    refute Jason.encode!(rows) =~ "The hero stays"

    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    decision_id = maps["decisions"][ctx.decision.id]
    restored = Repo.get!(Decision, decision_id)
    assert restored.id != ctx.decision.id
    assert restored.version == 3
    assert restored.status == :proposed
    assert restored.accepted_version == 2
    history = revisions(decision_id)
    assert Enum.map(history, & &1.operation) == ~w(propose accept revise)
    assert Enum.map(history, & &1.conclusion) == Enum.map(before, & &1.conclusion)
    assert Enum.map(history, & &1.source_context) == Enum.map(before, & &1.source_context)
    assert Enum.at(history, 1).actor_id == ctx.author.user.id

    for revision <- history do
      assert revision.responsible_id == ctx.author.user.id
      idea_source = Enum.find(revision.sources["items"], &(&1["type"] == "idea"))
      group_source = Enum.find(revision.sources["items"], &(&1["type"] == "group"))
      assert idea_source["id"] == maps["ideas"][ctx.first.id]
      assert group_source["id"] == maps["groups"][ctx.group.id]
      assert idea_source["version"] == 1
      assert group_source["version"] == 1
    end

    # Replaying the accepted request must not accept the newer pending proposal.
    assert {:ok, _} =
             Ideation.accept_decision(ctx.author, ctx.project.id, session_id, decision_id, 1, accept_key)

    assert Repo.get!(Decision, decision_id).accepted_version == 2
    assert length(revisions(decision_id)) == 3

    assert {:error, :not_found} =
             Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][ctx.second.id])

    for _ <- 1..3, do: assert(restore(ctx, capsule) == maps)
    assert Repo.aggregate(Decision, :count) == 1
    assert Repo.aggregate(Revision, :count) == 3
  end

  test "missing actors become unavailable without changing historical agreement or source versions", ctx do
    assert {:ok, _} = accept(ctx, ctx.decision.id, 1, Ecto.UUID.generate())
    capsule = capture(ctx)
    Repo.delete!(ctx.author.user)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    decision = Repo.get!(Decision, maps["decisions"][ctx.decision.id])
    assert decision.author_id == nil
    assert decision.status == :accepted
    assert decision.accepted_version == 2
    [proposed, accepted] = revisions(decision.id)
    assert proposed.actor_id == nil
    assert accepted.actor_id == nil
    assert proposed.responsible_id == nil
    assert accepted.responsible_id == nil
    source = Enum.find(proposed.sources["items"], &(&1["type"] == "idea"))
    assert source["author_id"] == nil
    assert source["version"] == 1
    assert restore(ctx, capsule) == maps
  end

  test "a receipt from a replaced generation cannot accept a proposal rolled back by recovery", ctx do
    capsule = capture(ctx)
    accept_key = Ecto.UUID.generate()
    assert {:ok, accepted} = accept(ctx, ctx.decision.id, 1, accept_key)
    accepted_at = accepted.accepted.inserted_at

    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    decision_id = maps["decisions"][ctx.decision.id]
    assert session_id != ctx.session.id
    assert decision_id != ctx.decision.id
    assert Repo.get!(Session, ctx.session.id).deleted_at
    count = Repo.aggregate(Revision, :count)

    # Both a stale browser ID and the restored current ID are fenced by the
    # logical session identity; neither can repeat an intentionally undone write.
    for id <- [ctx.decision.id, decision_id] do
      assert {:error, :idempotency_conflict} =
               Ideation.accept_decision(ctx.author, ctx.project.id, session_id, id, 1, accept_key)
    end

    assert Repo.aggregate(Revision, :count) == count
    assert %{version: 1, status: :proposed, accepted_version: nil} = Repo.get!(Decision, decision_id)
    assert [%{operation: "propose"}] = revisions(decision_id)
    assert Enum.at(revisions(ctx.decision.id), 1).inserted_at == accepted_at

    # A fresh explicit acceptance is still available after the restored preview.
    assert {:ok, accepted_again} =
             Ideation.accept_decision(ctx.author, ctx.project.id, session_id, decision_id, 1, Ecto.UUID.generate())

    assert accepted_again.status == :accepted
    assert accepted_again.version == 2
    assert length(revisions(decision_id)) == 2
  end

  test "replaced receipt keys do not fence a different logical session in the same project", ctx do
    capsule = capture(ctx)
    key = Ecto.UUID.generate()
    assert {:ok, _} = accept(ctx, ctx.decision.id, 1, key)
    restore(ctx, capsule)

    assert {:ok, session} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Another exploration"})
    other = %{ctx | session: session}
    idea = idea_fixture(other, %{visibility: :shared, title: "A separate shared source"})
    attrs = proposal_attrs(other, [%{type: "idea", id: idea.id}])

    assert {:ok, proposed} =
             Ideation.propose_decision(ctx.author, ctx.project.id, session.id, %{attrs | request_key: key})

    assert proposed.session_id == session.id
    assert proposed.version == 1
    assert [%{operation: "propose"}] = revisions(proposed.id)
  end

  test "private-mode import retains agreement history without exposing it or granting access", ctx do
    assert {:ok, _} = accept(ctx, ctx.decision.id, 1, Ecto.UUID.generate())
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, session.id, session.revision, true)
    capsule = capture(ctx)
    destination = project_fixture(ctx.owner.user)
    target = %{ctx | project: destination}
    maps = restore(target, capsule)
    session_id = maps["sessions"][ctx.session.id]
    decision_id = maps["decisions"][ctx.decision.id]
    assert Repo.get!(Decision, decision_id).accepted_version == 2
    assert Enum.at(revisions(decision_id), 1).operation == "accept"
    assert {:error, :private_mode} = Ideation.get_decision(ctx.owner, destination.id, session_id, decision_id)
    assert {:error, :not_found} = Ideation.get_decision(ctx.author, destination.id, session_id, decision_id)
    assert restore(target, capsule) == maps
  end

  test "version-five capsules retain their content and normalize empty decisions", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()
    legacy = data |> Map.put("version", 5) |> update_in(["rows"], &Map.drop(&1, ~w(decisions decision_revisions)))
    assert {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["version"] == 6
    assert normalized["rows"]["decisions"] == []
    assert normalized["rows"]["decision_revisions"] == []
    maps = restore(ctx, capsule)
    assert maps["decisions"] == %{}
    assert maps["decision_revisions"] == %{}
    assert Repo.aggregate(Decision, :count) == 1
    assert restore(ctx, capsule) == maps
  end

  test "malformed decision history and unpublished or forged source snapshots fail before replacement", ctx do
    assert {:ok, _} = accept(ctx, ctx.decision.id, 1, Ecto.UUID.generate())

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.first.id,
               1,
               edit_attrs(%{body: "<p>A private unpublished change.</p>"})
             )

    capsule = capture(ctx)
    {:ok, data} = Capsule.open(capsule)
    [first | _] = data["rows"]["decision_revisions"]
    source = Enum.find(first["sources"]["items"], &(&1["type"] == "idea"))
    {:ok, plaintext} = first["source_context"] |> Base.decode64!() |> Vault.decrypt()
    context = Jason.decode!(plaintext)
    forged_context = put_in(context, [source["identity"], "body"], "<p>A private unpublished change.</p>")
    {:ok, forged_bytes} = forged_context |> Jason.encode!() |> Vault.encrypt()

    mutations = [
      fn data -> put_in(data, ["rows", "decisions", Access.at(0), "accepted_version"], 1) end,
      fn data -> put_in(data, ["rows", "decisions", Access.at(0), "status"], "proposed") end,
      fn data -> put_in(data, ["rows", "decisions", Access.at(0), "version"], 99) end,
      fn data -> put_in(data, ["rows", "decision_revisions", Access.at(0), "operation"], "accept") end,
      fn data -> put_in(data, ["rows", "decision_revisions", Access.at(0), "responsible_id"], -1) end,
      fn data -> put_in(data, ["rows", "decision_revisions", Access.at(1), "actor_id"], ctx.facilitator.user.id) end,
      fn data -> put_in(data, ["rows", "decision_revisions", Access.at(0), "request_key"], "invalid") end,
      fn data -> put_in(data, ["rows", "decision_revisions", Access.at(0), "fingerprint"], "invalid") end,
      fn data ->
        put_in(data, ["rows", "decision_revisions", Access.at(0), "sources", "items", Access.at(0), "version"], 2)
      end,
      fn data ->
        put_in(
          data,
          ["rows", "decision_revisions", Access.at(0), "sources", "items", Access.at(0), "identity"],
          Ecto.UUID.generate()
        )
      end,
      fn data ->
        update_in(
          data,
          ["rows", "decision_revisions"],
          &Enum.map(&1, fn row -> Map.put(row, "source_context", Base.encode64(forged_bytes)) end)
        )
      end,
      fn data ->
        put_in(data, ["rows", "decision_revisions", Access.at(1), "conclusion"], encrypted("Changed by acceptance"))
      end,
      fn data -> update_in(data, ["rows", "decision_revisions"], &tl/1) end
    ]

    for mutate <- mutations do
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(mutate.(data)))
      assert Repo.get!(Decision, ctx.decision.id).accepted_version == 2
      assert Repo.aggregate(Session, :count) == 1
    end

    assert capture(ctx) == capsule
  end

  test "a capsule cannot restore more decisions than the ordinary reader supports", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()
    [decision] = data["rows"]["decisions"]
    [revision] = data["rows"]["decision_revisions"]

    pad = fn count ->
      decisions =
        for number <- 1..count,
            do: %{decision | "id" => 900_000 + number, "recovery_identity" => identity()}

      revisions =
        for number <- 1..count do
          %{
            revision
            | "id" => 900_000 + number,
              "decision_id" => 900_000 + number,
              "recovery_identity" => identity(),
              "request_key" => identity()
          }
        end

      data
      |> update_in(["rows", "decisions"], &(&1 ++ decisions))
      |> update_in(["rows", "decision_revisions"], &(&1 ++ revisions))
    end

    assert GraphValidation.valid?(pad.(99)["rows"])
    refute GraphValidation.valid?(pad.(100)["rows"])
    assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(pad.(100)))
    assert Repo.aggregate(Decision, :count) == 1
  end

  defp proposal_attrs(ctx, selections) do
    {:ok, sources} = Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, selections)

    %{
      request_key: Ecto.UUID.generate(),
      title: "Keep the village motivation",
      conclusion: "The hero stays with the village.",
      reason: "It connects both shared motives.",
      responsible_id: ctx.author.user.id,
      sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity]))
    }
  end

  defp accept(ctx, id, version, key),
    do: Ideation.accept_decision(ctx.author, ctx.project.id, ctx.session.id, id, version, key)

  defp revisions(id), do: Repo.all(from r in Revision, where: r.decision_id == ^id, order_by: r.number)

  defp capture(ctx) do
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok,
         ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
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
      Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end

  defp identity, do: Base.encode64(:crypto.strong_rand_bytes(16))

  defp encrypted(text) do
    {:ok, bytes} = Vault.encrypt(text)
    Base.encode64(bytes)
  end

  defp authenticate(data), do: %{"version" => 1, "ciphertext" => encrypted(Jason.encode!(data))}
end
