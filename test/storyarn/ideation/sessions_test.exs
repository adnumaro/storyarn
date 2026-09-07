defmodule Storyarn.Ideation.SessionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Ideation
  alias Storyarn.Ideation.Sessions.Revision
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Projects

  setup do
    owner = user_fixture()
    project = project_fixture(owner)
    editor = user_fixture()
    membership = membership_fixture(project, editor)

    %{
      owner: owner,
      project: project,
      owner_scope: user_scope_fixture(owner),
      editor: editor,
      editor_scope: user_scope_fixture(editor),
      editor_membership: membership
    }
  end

  test "creates several sessions in an empty project with independent safe defaults", ctx do
    assert {:ok, first} = Ideation.create_session(ctx.editor_scope, ctx.project.id, %{title: "  Character arcs  "})
    assert first.title == "Character arcs"
    assert first.facilitator_id == ctx.editor.id
    assert first.decision_owner_id == ctx.editor.id
    assert first.created_by_id == ctx.editor.id
    assert is_nil(first.objective)
    assert is_nil(first.context)
    assert first.revision == 1
    assert first.configuration_version == 1
    refute first.configuration.rounds_enabled
    refute first.configuration.timer_enabled
    assert first.configuration.default_visibility == :private
    assert first.configuration.publication_policy == :author_only

    assert {:ok, second} = Ideation.create_session(ctx.editor_scope, ctx.project.id, %{title: "Ending options"})
    assert {:ok, [^second, ^first]} = Ideation.list_sessions(ctx.owner_scope, ctx.project.id)
    assert {:ok, [revision]} = Ideation.list_session_revisions(ctx.owner_scope, ctx.project.id, first.id)
    assert revision.actor_id == ctx.editor.id
    assert revision.action == :created
    assert revision.snapshot["title"] == first.title
  end

  test "rejects invalid content and cannot assign identity, roles or state through content attributes", ctx do
    assert {:error, changeset} = Ideation.create_session(ctx.editor_scope, ctx.project.id, %{title: "   "})
    assert errors_on(changeset).title == ["can't be blank"]
    assert Repo.aggregate(Session, :count) == 0
    assert Repo.aggregate(Revision, :count) == 0

    assert {:ok, session} =
             Ideation.create_session(ctx.editor_scope, ctx.project.id, %{
               title: "Ideas",
               project_id: -1,
               created_by_id: ctx.owner.id,
               facilitator_id: ctx.owner.id,
               status: "archived",
               revision: 99
             })

    assert session.project_id == ctx.project.id
    assert session.created_by_id == ctx.editor.id
    assert session.facilitator_id == ctx.editor.id
    assert session.status == :open
    assert session.revision == 1

    assert {:error, changeset} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{
               objective: String.duplicate("x", 4001)
             })

    assert errors_on(changeset).objective != []
    assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "retains exact revision history, rejects stale edits, and versions only effective configuration changes", ctx do
    session = create_session(ctx)

    assert {:ok, updated} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{objective: "Explore motives"})

    assert updated.revision == 2
    assert updated.configuration_version == 1

    assert {:error, :stale_revision} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{title: "Stale title"})

    assert {:error, :invalid_revision} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, nil, %{title: "No version"})

    assert {:ok, ^updated} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)

    assert {:ok, configured} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 2, %{
               configuration: %{timer_enabled: true, timer_seconds: 300}
             })

    assert configured.revision == 3
    assert configured.configuration_version == 2
    refute configured.configuration.rounds_enabled
    assert configured.configuration.default_visibility == :private

    assert {:ok, ^configured} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 3, %{
               configuration: %{timer_enabled: true, timer_seconds: 300}
             })

    assert {:ok, [latest, edited, original]} =
             Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, session.id)

    assert latest.number == 3
    assert edited.snapshot["objective"] == "Explore motives"
    assert original.snapshot["objective"] == nil
    assert original.snapshot["configuration"]["timer_enabled"] == false
  end

  test "empty and invalid titles return validation errors without losing the persisted session", ctx do
    session = create_session(ctx)

    for key <- [:title, "title"], value <- [nil, "", " \t\n ", 42, %{}] do
      assert {:error, changeset} =
               Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{key => value})

      assert errors_on(changeset).title != []
      assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
      assert {:ok, [%{number: 1}]} = Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, session.id)
    end

    assert {:ok, updated} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{title: "  Revised title  "})

    assert updated.title == "Revised title"
    assert updated.revision == 2
  end

  test "configuration cannot be removed and failed edits preserve both content and history", ctx do
    session = create_session(ctx)

    for key <- [:configuration, "configuration"] do
      assert {:error, changeset} =
               Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{key => nil})

      assert errors_on(changeset).configuration == ["can't be blank"]
      assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
      assert {:ok, [%{number: 1}]} = Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, session.id)
    end

    assert {:ok, ^session} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{configuration: %{}})

    assert {:ok, updated} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{
               configuration: %{rounds_enabled: true}
             })

    assert updated.configuration_version == 2
  end

  test "rounds and publication settings do not require a clock or each other", ctx do
    assert {:ok, session} =
             Ideation.create_session(ctx.editor_scope, ctx.project.id, %{
               title: "Open discussion",
               configuration: %{rounds_enabled: true, default_visibility: "shared"}
             })

    assert session.configuration.rounds_enabled
    refute session.configuration.timer_enabled
    assert session.configuration.publication_policy == :author_only

    assert {:error, changeset} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{
               configuration: %{timer_enabled: true}
             })

    assert errors_on(changeset).configuration.timer_seconds == ["can't be blank"]

    assert {:error, _changeset} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{
               configuration: %{publication_policy: "auto_reveal", default_visibility: nil}
             })

    assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
  end

  test "archive and reopen preserve identity and history without admitting ordinary edits", ctx do
    session = create_session(ctx)
    assert {:ok, archived} = Ideation.archive_session(ctx.editor_scope, ctx.project.id, session.id, 1)
    assert archived.archived_at
    assert archived.status == :archived
    assert {:ok, []} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id)
    assert {:ok, [^archived]} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id, status: :archived)
    assert {:ok, ^archived} = Ideation.archive_session(ctx.editor_scope, ctx.project.id, session.id, 2)

    assert {:error, :session_archived} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 2, %{title: "No"})

    assert {:error, :stale_revision} = Ideation.reopen_session(ctx.editor_scope, ctx.project.id, session.id, 1)

    assert {:ok, reopened} = Ideation.reopen_session(ctx.editor_scope, ctx.project.id, session.id, 2)
    assert reopened.status == :open
    assert reopened.id == session.id
    assert reopened.configuration == session.configuration
    assert reopened.archived_at == nil
    assert {:ok, ^reopened} = Ideation.reopen_session(ctx.editor_scope, ctx.project.id, session.id, 3)
    assert {:ok, history} = Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, session.id)
    assert Enum.map(history, & &1.action) == [:reopened, :archived, :created]
  end

  test "all reads and mutations reject foreign project scope and outsiders", ctx do
    session = create_session(ctx)
    outsider_scope = user_scope_fixture()
    other = project_fixture(outsider_scope.user)

    for {scope, project_id} <- [{outsider_scope, ctx.project.id}, {outsider_scope, other.id}] do
      assert {:error, _} = Ideation.get_session(scope, project_id, session.id)
      assert {:error, _} = Ideation.list_session_revisions(scope, project_id, session.id)
      assert {:error, _} = Ideation.update_session(scope, project_id, session.id, 1, %{title: "Wrong project"})
      assert {:error, _} = Ideation.archive_session(scope, project_id, session.id, 1)
      assert {:error, _} = Ideation.reopen_session(scope, project_id, session.id, 1)

      assert {:error, _} =
               Ideation.assign_session_responsibilities(scope, project_id, session.id, 1, %{facilitator_id: scope.user.id})
    end

    assert {:error, _} = Ideation.list_sessions(outsider_scope, ctx.project.id)
    assert {:error, _} = Ideation.create_session(outsider_scope, ctx.project.id, %{title: "No access"})
  end

  test "viewers can read shared metadata; being decision owner does not grant session management", ctx do
    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")
    viewer_scope = user_scope_fixture(viewer)
    session = create_session(ctx)

    assert {:ok, ^session} = Ideation.get_session(viewer_scope, ctx.project.id, session.id)
    assert {:ok, [_revision]} = Ideation.list_session_revisions(viewer_scope, ctx.project.id, session.id)
    assert {:error, :unauthorized} = Ideation.create_session(viewer_scope, ctx.project.id, %{title: "No"})
    assert {:error, :unauthorized} = Ideation.archive_session(viewer_scope, ctx.project.id, session.id, 1)

    assert {:ok, delegated} =
             Ideation.assign_session_responsibilities(ctx.editor_scope, ctx.project.id, session.id, 1, %{
               facilitator_id: ctx.owner.id
             })

    assert delegated.decision_owner_id == ctx.editor.id

    assert {:error, :unauthorized} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 2, %{title: "Old facilitator"})

    assert {:error, :unauthorized} =
             Ideation.assign_session_responsibilities(ctx.editor_scope, ctx.project.id, session.id, 2, %{
               facilitator_id: ctx.editor.id
             })
  end

  test "delegation checks effective access and commits neither partial responsibility nor history", ctx do
    session = create_session(ctx)
    outsider = user_fixture()

    assert {:error, changeset} =
             Ideation.assign_session_responsibilities(ctx.editor_scope, ctx.project.id, session.id, 1, %{
               facilitator_id: ctx.owner.id,
               decision_owner_id: outsider.id
             })

    assert errors_on(changeset).decision_owner_id == ["must be a current project editor"]
    assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "repairs either responsibility independently after the other account is deleted", ctx do
    for missing_field <- [:facilitator_id, :decision_owner_id] do
      departing =
        %User{}
        |> User.email_changeset(%{email: unique_user_email()})
        |> User.confirm_changeset()
        |> Repo.insert!()

      membership_fixture(ctx.project, departing)
      session = create_session(ctx)

      assert {:ok, assigned} =
               Ideation.assign_session_responsibilities(ctx.editor_scope, ctx.project.id, session.id, 1, %{
                 missing_field => departing.id
               })

      Repo.delete!(departing)

      assert {:ok, orphaned} = Ideation.get_session(ctx.owner_scope, ctx.project.id, session.id)
      assert Map.fetch!(orphaned, missing_field) == nil
      other_field = if missing_field == :facilitator_id, do: :decision_owner_id, else: :facilitator_id

      assert {:ok, repaired} =
               Ideation.assign_session_responsibilities(
                 ctx.owner_scope,
                 ctx.project.id,
                 session.id,
                 assigned.revision,
                 %{other_field => ctx.owner.id}
               )

      assert Map.fetch!(repaired, other_field) == ctx.owner.id
      assert Map.fetch!(repaired, missing_field) == nil
      assert repaired.revision == assigned.revision + 1

      assert {:ok, [latest | _older]} = Ideation.list_session_revisions(ctx.owner_scope, ctx.project.id, session.id)
      assert latest.snapshot[Atom.to_string(missing_field)] == nil
      assert latest.snapshot[Atom.to_string(other_field)] == ctx.owner.id
    end
  end

  test "explicit blank responsibility assignments are rejected without clearing existing roles", ctx do
    session = create_session(ctx)

    for field <- [:facilitator_id, :decision_owner_id], value <- [nil, "", " "] do
      assert {:error, changeset} =
               Ideation.assign_session_responsibilities(ctx.editor_scope, ctx.project.id, session.id, 1, %{
                 field => value
               })

      assert Map.fetch!(errors_on(changeset), field) != []
      assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
      assert {:ok, [%{number: 1}]} = Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, session.id)
    end
  end

  test "rechecks downgrade and explicit denial on an already obtained scope, and owner can replace a departed facilitator",
       ctx do
    session = create_session(ctx)
    assert {:ok, _} = Projects.update_member_role(ctx.owner_scope, ctx.project.id, ctx.editor_membership.id, "viewer")

    assert {:ok, ^session} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)

    assert {:error, :unauthorized} =
             Ideation.update_session(ctx.editor_scope, ctx.project.id, session.id, 1, %{title: "Old socket"})

    assert {:error, :unauthorized} = Ideation.archive_session(ctx.editor_scope, ctx.project.id, session.id, 1)

    assert {:error, _} =
             Ideation.assign_session_responsibilities(ctx.owner_scope, ctx.project.id, session.id, 1, %{
               decision_owner_id: ctx.editor.id,
               facilitator_id: ctx.editor.id
             })

    assert {:ok, _} = Projects.remove_member(ctx.owner_scope, ctx.project.id, ctx.editor_membership.id)
    assert {:error, _} = Ideation.get_session(ctx.editor_scope, ctx.project.id, session.id)
    assert {:error, _} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id)
    assert {:error, _} = Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, session.id)

    assert {:ok, repaired} =
             Ideation.assign_session_responsibilities(ctx.owner_scope, ctx.project.id, session.id, 1, %{
               facilitator_id: ctx.owner.id,
               decision_owner_id: ctx.owner.id
             })

    assert repaired.facilitator_id == ctx.owner.id
    assert {:ok, _} = Ideation.archive_session(ctx.owner_scope, ctx.project.id, session.id, 2)
  end

  test "a direct viewer role denies writes despite inherited workspace editing access", ctx do
    workspace = %{id: ctx.project.workspace_id}
    admin = user_fixture()
    workspace_membership_fixture(workspace, admin, "admin")
    scope = user_scope_fixture(admin)
    assert {:ok, session} = Ideation.create_session(scope, ctx.project.id, %{title: "Inherited access"})

    membership_fixture(ctx.project, admin, "viewer")
    assert {:ok, ^session} = Ideation.get_session(scope, ctx.project.id, session.id)
    assert {:ok, [^session]} = Ideation.list_sessions(scope, ctx.project.id)
    assert {:error, :unauthorized} = Ideation.update_session(scope, ctx.project.id, session.id, 1, %{title: "Denied"})
  end

  test "lists and history are bounded and paginated within the authorized project", ctx do
    first = create_session(ctx)
    second = create_session(ctx)
    assert {:ok, [^second]} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id, limit: 1)
    assert {:ok, [^first]} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id, before_id: second.id)
    assert {:error, :invalid_options} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id, limit: 201)
    assert {:error, :invalid_options} = Ideation.list_sessions(ctx.editor_scope, ctx.project.id, status: "arbitrary")

    assert {:ok, _} = Ideation.update_session(ctx.editor_scope, ctx.project.id, first.id, 1, %{title: "Revised"})
    assert {:ok, [latest]} = Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, first.id, limit: 1)

    assert {:ok, [original]} =
             Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, first.id, before_id: latest.id)

    assert original.number == 1

    assert {:error, :invalid_options} =
             Ideation.list_session_revisions(ctx.editor_scope, ctx.project.id, first.id, limit: 0)
  end

  test "soft-deleted projects remain inaccessible without removing session history", ctx do
    session = create_session(ctx)
    assert {:ok, _} = Projects.delete_project(ctx.owner_scope, ctx.project.id)
    assert {:error, :not_found} = Ideation.get_session(ctx.owner_scope, ctx.project.id, session.id)
    assert {:error, :not_found} = Ideation.list_sessions(ctx.owner_scope, ctx.project.id)
    assert {:error, :not_found} = Ideation.list_session_revisions(ctx.owner_scope, ctx.project.id, session.id)
    assert {:error, :not_found} = Ideation.reopen_session(ctx.owner_scope, ctx.project.id, session.id, 1)
    assert Repo.get!(Session, session.id).title == session.title
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "transaction-aware Projects port fails outside a transaction", ctx do
    # Sandbox itself uses a transaction; the domain port must also demand an
    # explicit caller transaction before issuing authorization locks.
    refute Repo.in_transaction?()

    assert {:error, :authorization_transaction_required} =
             Projects.authorize_locked(ctx.editor_scope, ctx.project.id, :edit_content)
  end

  defp create_session(ctx) do
    {:ok, session} = Ideation.create_session(ctx.editor_scope, ctx.project.id, %{title: "Ideas"})
    session
  end
end
