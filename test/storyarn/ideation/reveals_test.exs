defmodule Storyarn.Ideation.RevealsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Projects

  setup do
    ideation_fixture()
  end

  test "an author publishes an exact revision and later edits stay private", ctx do
    original = idea_fixture(ctx, %{body: "Only the author knows this"})
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, original.id)
    shared = publish_idea(ctx, original)
    assert shared.visibility == :shared
    assert shared.published_revision == 1

    assert {:ok, changed} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               original.id,
               1,
               edit_attrs(%{title: "Private title", body: "A secret rewrite"})
             )

    assert changed.has_unpublished_changes

    for actor <- [ctx.peer, ctx.facilitator, ctx.owner, ctx.viewer] do
      assert {:ok, visible} = Ideation.get_idea(actor, ctx.project.id, ctx.session.id, original.id)
      assert visible.body == original.body
      assert visible.title == original.title
      assert visible.revision == 1
      refute Map.has_key?(visible, :current_revision)
      refute Map.has_key?(visible, :has_unpublished_changes)
      assert {:ok, [%{number: 1}]} = Ideation.list_idea_revisions(actor, ctx.project.id, ctx.session.id, original.id)
    end

    published = publish_idea(ctx, changed)
    assert published.published_revision == 2

    assert {:ok, [%{number: 2}, %{number: 1}]} =
             Ideation.list_idea_revisions(ctx.peer, ctx.project.id, ctx.session.id, original.id)
  end

  test "unpublished historical drafts never become visible when a later revision is shared", ctx do
    original = idea_fixture(ctx, %{body: "Never share this draft"})

    assert {:ok, edited} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               original.id,
               1,
               edit_attrs(%{body: "Public contribution"})
             )

    publish_idea(ctx, edited)
    assert {:ok, [revision]} = Ideation.list_idea_revisions(ctx.viewer, ctx.project.id, ctx.session.id, original.id)
    assert revision.number == 2
    assert revision.body == "Public contribution"

    assert {:error, :not_found} =
             Ideation.derive_idea(ctx.peer, ctx.project.id, ctx.session.id, original.id, 1, idea_attrs())
  end

  test "facilitators can prepare and reveal consenting drafts without reading their content", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    idea = assisted_idea(ctx, %{body: "Hidden before reveal"})
    author_only = idea_fixture(ctx, %{configuration_version: 2, body: "Not part of the agreement"}, ctx.peer)
    assert {:error, :not_found} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, idea.id)
    assert {:ok, []} = Ideation.list_ideas(ctx.facilitator, ctx.project.id, ctx.session.id)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert operation.manifest == [%{"idea_id" => idea.id, "revision" => 1}]
    refute inspect(operation) =~ "Hidden"
    refute inspect(operation) =~ "Not part"
    assert {:ok, completed} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, operation.id)
    assert completed.status == :completed
    assert {:ok, visible} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, idea.id)
    assert visible.body == idea.body
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, ctx.session.id, author_only.id)
  end

  test "neither the owner nor facilitator can reveal an author-only draft", ctx do
    idea = idea_fixture(ctx)

    for actor <- [ctx.owner, ctx.facilitator, ctx.peer] do
      assert {:error, :not_found} =
               Ideation.prepare_idea_reveal(actor, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), [
                 %{idea_id: idea.id, revision: 1}
               ])
    end

    assert {:error, :unauthorized} =
             Ideation.prepare_idea_reveal(ctx.peer, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert Repo.aggregate(Reveal, :count) == 0
    assert Repo.aggregate(Publication, :count) == 0
  end

  test "consent is explicit and configuration changes never broaden existing consent", ctx do
    before_change = idea_fixture(ctx)
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    default_consent = idea_fixture(ctx, %{configuration_version: 2})
    assisted = assisted_idea(ctx)
    assert default_consent.publication_consent == :author_only

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.owner, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert operation.manifest == [%{"idea_id" => assisted.id, "revision" => 1}]

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               before_change.id,
               1,
               edit_attrs(%{publication_consent: :facilitator_assisted, configuration_version: 2})
             )

    assert Repo.get!(Idea, before_change.id).publication_consent == :author_only
    assert {:ok, _} = Ideation.reveal_ideas(ctx.owner, ctx.project.id, ctx.session.id, operation.id)
    assert Repo.get!(Idea, before_change.id).published_revision == nil
  end

  test "late ideas are excluded even when prepare is retried after they arrive", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    early = assisted_idea(ctx)
    key = Ecto.UUID.generate()
    assert {:ok, operation} = Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, key)
    late = assisted_idea(ctx)
    assert {:ok, ^operation} = Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, key)
    assert {:ok, _} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, operation.id)
    assert Repo.get!(Idea, early.id).published_revision == 1
    assert Repo.get!(Idea, late.id).published_revision == nil
  end

  test "a concurrent edit makes the entire prepared reveal stale and recoverable", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    first = assisted_idea(ctx)
    second = assisted_idea(ctx)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               second.id,
               1,
               edit_attrs(%{body: "New draft after preparation"})
             )

    assert {:error, :stale_reveal} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, operation.id)
    assert Repo.get!(Idea, first.id).published_revision == nil
    assert Repo.get!(Idea, second.id).published_revision == nil
    assert Repo.get!(Reveal, operation.id).status == :prepared
    assert Repo.aggregate(Publication, :count) == 0

    assert {:ok, refreshed} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert {:ok, _} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, refreshed.id)
    assert Repo.get!(Idea, second.id).published_revision == 2
  end

  test "retries and overlapping reveals create one publication per revision", ctx do
    idea = idea_fixture(ctx)
    targets = [%{idea_id: idea.id, revision: 1}]

    assert {:ok, first} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), targets)

    assert {:ok, second} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), targets)

    assert {:ok, completed} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, first.id)
    assert {:ok, ^completed} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, first.id)
    assert {:ok, _} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, second.id)
    assert Repo.aggregate(Publication, :count) == 1
    assert {:ok, ^completed} = Ideation.get_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, first.id)
    assert {:error, :not_found} = Ideation.get_idea_reveal(ctx.owner, ctx.project.id, ctx.session.id, first.id)
  end

  test "a prepared reveal cannot be stolen and rechecks current delegated authority", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    idea = assisted_idea(ctx)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert {:error, :not_found} = Ideation.reveal_ideas(ctx.peer, ctx.project.id, ctx.session.id, operation.id)

    assert {:ok, _} =
             Ideation.assign_session_responsibilities(ctx.owner, ctx.project.id, ctx.session.id, ctx.session.revision, %{
               facilitator_id: ctx.peer.user.id
             })

    assert {:error, :not_found} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, operation.id)
    assert Repo.get!(Idea, idea.id).published_revision == nil
  end

  test "switching to open creation does not publish old drafts and returning to private does not unpublish", ctx do
    old_draft = idea_fixture(ctx)
    ctx = configure_session(ctx, %{default_visibility: :shared})
    shared = idea_fixture(ctx, %{configuration_version: 2})
    assert shared.visibility == :shared
    assert {:ok, [visible]} = Ideation.list_ideas(ctx.viewer, ctx.project.id, ctx.session.id)
    assert visible.id == shared.id
    assert {:error, :not_found} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, old_draft.id)
    ctx = configure_session(ctx, %{default_visibility: :private})
    assert {:ok, %{visibility: :shared}} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, shared.id)
    assert Repo.get!(Idea, old_draft.id).publication_consent == :author_only
  end

  test "invalid selections and reused request keys are rejected without partial operations", ctx do
    first = idea_fixture(ctx)
    second = idea_fixture(ctx)
    key = Ecto.UUID.generate()
    targets = [%{idea_id: first.id, revision: 1}]
    assert {:ok, operation} = Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, key, targets)

    assert {:error, :idempotency_conflict} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, key, [
               %{idea_id: second.id, revision: 1}
             ])

    for selection <- [[], %{}, [nil], targets ++ targets, [%{idea_id: first.id, revision: -1}], List.duplicate(%{}, 201)] do
      assert {:error, :invalid_selection} =
               Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), selection)
    end

    assert Repo.aggregate(Reveal, :count) == 1
    assert Repo.get!(Reveal, operation.id).status == :prepared
  end

  test "current project downgrade blocks an already prepared reveal", ctx do
    idea = idea_fixture(ctx)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), [
               %{idea_id: idea.id, revision: 1}
             ])

    membership =
      Repo.get_by!(Storyarn.Projects.ProjectMembership, project_id: ctx.project.id, user_id: ctx.author.user.id)

    assert {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")
    assert {:error, :unauthorized} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, operation.id)
    assert Repo.aggregate(Publication, :count) == 0
  end

  defp assisted_idea(ctx, attrs \\ %{}) do
    idea_fixture(
      ctx,
      Map.merge(
        %{configuration_version: ctx.session.configuration_version, publication_consent: :facilitator_assisted},
        attrs
      )
    )
  end
end
