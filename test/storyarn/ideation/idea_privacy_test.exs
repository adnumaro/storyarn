defmodule Storyarn.Ideation.IdeaPrivacyTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectMembership

  setup do
    ideation_fixture()
  end

  test "all read projections deny others' private drafts and counts", ctx do
    idea = idea_fixture(ctx, %{title: "Private title", body: "Private draft"})

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "Private current text"})
             )

    attrs = edit_attrs(%{body: "Private losing text"})

    assert {:error, {:edit_conflict, _}} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)

    for actor <- [ctx.peer, ctx.facilitator, ctx.owner, ctx.viewer] do
      assert {:error, :not_found} = Ideation.get_idea(actor, ctx.project.id, ctx.session.id, idea.id)

      assert {:ok, []} = Ideation.list_ideas(actor, ctx.project.id, ctx.session.id, state: :all, visibility: :private)
      assert {:ok, %{active: 0, parked: 0, discarded: 0}} = Ideation.count_ideas(actor, ctx.project.id, ctx.session.id)
    end
  end

  test "published projections contain no unpublished title, content, revision activity or conflicts", ctx do
    idea = ctx |> idea_fixture(%{body: "Public"}) |> then(&publish_idea(ctx, &1))

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{title: "DO_NOT_LEAK_TITLE", body: "DO_NOT_LEAK_BODY"})
             )

    attrs = edit_attrs(%{body: "DO_NOT_LEAK_CONFLICT"})

    assert {:error, {:edit_conflict, _}} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)

    for actor <- [ctx.peer, ctx.facilitator, ctx.owner, ctx.viewer] do
      {:ok, visible} = Ideation.get_idea(actor, ctx.project.id, ctx.session.id, idea.id)
      {:ok, listed} = Ideation.list_ideas(actor, ctx.project.id, ctx.session.id)
      payload = Jason.encode!(%{idea: visible, ideas: listed})
      refute payload =~ "DO_NOT_LEAK"
      refute Map.has_key?(visible, :current_revision)
      refute Map.has_key?(visible, :publication_consent)
    end
  end

  test "only authors edit content or creative state even after publication", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))

    for actor <- [ctx.peer, ctx.facilitator, ctx.owner] do
      assert {:error, :not_found} =
               Ideation.update_idea(
                 actor,
                 ctx.project.id,
                 ctx.session.id,
                 idea.id,
                 1,
                 edit_attrs(%{body: "Unauthorized edit", state: :discarded})
               )
    end

    assert {:error, :unauthorized} =
             Ideation.update_idea(
               ctx.viewer,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "Unauthorized edit"})
             )

    assert {:ok, %{body: "<p>Original idea</p>", state: :active}} =
             Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
  end

  test "project and session identities are enforced independently", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    other_project = project_fixture(ctx.owner.user)
    membership_fixture(other_project, ctx.author.user)
    {:ok, other_session} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Other session"})
    {:ok, foreign_session} = Ideation.create_session(ctx.author, other_project.id, %{title: "Other project"})

    for {project_id, session_id} <- [
          {ctx.project.id, other_session.id},
          {other_project.id, ctx.session.id},
          {other_project.id, foreign_session.id}
        ] do
      assert {:error, :not_found} = Ideation.get_idea(ctx.author, project_id, session_id, idea.id)

      assert {:error, :not_found} =
               Ideation.update_idea(
                 ctx.author,
                 project_id,
                 session_id,
                 idea.id,
                 1,
                 edit_attrs(%{body: "Wrong context"})
               )
    end

    outsider = user_scope_fixture()
    assert {:error, _} = Ideation.list_ideas(outsider, ctx.project.id, ctx.session.id)
    assert {:error, _} = Ideation.create_idea(outsider, ctx.project.id, ctx.session.id, idea_attrs())
  end

  test "cached scopes lose both read and write access after membership removal", ctx do
    idea = idea_fixture(ctx)
    membership = Repo.get_by!(ProjectMembership, project_id: ctx.project.id, user_id: ctx.author.user.id)
    Repo.delete!(membership)
    assert {:error, _} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert {:error, _} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert {:error, _} = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)

    assert {:error, _} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{body: "Denied"}))

    membership_fixture(ctx.project, ctx.author.user)
    assert {:ok, ^idea} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
  end

  test "inherited project access works but a direct viewer role blocks writing", ctx do
    user = user_fixture()
    workspace_membership_fixture(%{id: ctx.project.workspace_id}, user, "member")
    scope = user_scope_fixture(user)
    assert {:ok, idea} = Ideation.create_idea(scope, ctx.project.id, ctx.session.id, idea_attrs())
    membership_fixture(ctx.project, user, "viewer")
    assert {:ok, ^idea} = Ideation.get_idea(scope, ctx.project.id, ctx.session.id, idea.id)

    assert {:error, :unauthorized} =
             Ideation.update_idea(scope, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{body: "Denied"}))
  end

  test "archive preserves drafts and publications while blocking contribution mutations", ctx do
    idea = idea_fixture(ctx)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.author, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), [
               %{idea_id: idea.id, revision: 1}
             ])

    assert {:ok, archived} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 1)
    assert {:ok, ^idea} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert {:error, :session_archived} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())

    assert {:error, :session_archived} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{body: "Denied"}))

    assert {:error, :session_archived} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, operation.id)
    assert {:ok, _} = Ideation.reopen_session(ctx.facilitator, ctx.project.id, ctx.session.id, archived.revision)
    assert {:ok, _} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, operation.id)
  end

  test "account deletion never transfers private drafts or author rights", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    private_idea = idea_fixture(ctx, %{configuration_version: 2, publication_consent: :facilitator_assisted})
    shared = ctx |> idea_fixture(%{configuration_version: 2}) |> then(&publish_idea(ctx, &1))
    Repo.delete!(Repo.get!(User, ctx.author.user.id))
    assert Repo.get!(Idea, private_idea.id).author_id == nil
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, ctx.session.id, private_idea.id)

    assert {:ok, %{author_id: nil, body: "<p>Original idea</p>"}} =
             Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, shared.id)

    assert {:ok, %{manifest: []}} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert {:error, :not_found} =
             Ideation.update_idea(
               ctx.owner,
               ctx.project.id,
               ctx.session.id,
               shared.id,
               1,
               edit_attrs(%{body: "Cannot become author"})
             )
  end

  test "project soft deletion denies access and hard deletion removes all owned records", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    assert {:ok, _} = Projects.delete_project(ctx.owner, ctx.project.id)
    assert {:error, _} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert Repo.get!(Idea, idea.id).id == idea.id
    Repo.delete!(ctx.project)
    for schema <- [Idea, Revision, Edit, Reveal, Publication], do: assert(Repo.aggregate(schema, :count) == 0)
  end

  test "invalidations contain no content and private changes never reach shared subscribers", ctx do
    assert :ok = Ideation.subscribe_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    idea = idea_fixture(ctx, %{body: "SECRET"})
    refute_receive {:ideation_changed, _}
    publish_idea(ctx, idea)
    session_id = ctx.session.id
    assert_receive {:ideation_changed, ^session_id}

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "UNPUBLISHED SECRET"})
             )

    refute_receive {:ideation_changed, _}
  end

  test "private authors receive invalidations only for committed saves and outer transactions are rejected", ctx do
    assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)
    idea = idea_fixture(ctx)
    session_id = ctx.session.id
    assert_receive {:ideation_changed, ^session_id}

    assert {:error, _} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{body: nil}))

    refute_receive {:ideation_changed, _}

    assert {:ok, {:error, :idea_requires_outer_transaction}} =
             Repo.transaction(fn ->
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())
             end)

    refute_receive {:ideation_changed, _}
    assert Repo.aggregate(Idea, :count) == 1
  end
end
