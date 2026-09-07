defmodule Storyarn.IdeationFixtures do
  @moduledoc false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Ideation
  alias Storyarn.Repo

  def ideation_fixture do
    owner = user_fixture()
    project = project_fixture(owner)

    actors =
      for role <- [:author, :peer, :facilitator, :viewer], into: %{} do
        user =
          %User{} |> User.email_changeset(%{email: unique_user_email()}) |> User.confirm_changeset() |> Repo.insert!()

        membership_fixture(project, user, if(role == :viewer, do: "viewer", else: "editor"))
        {role, user_scope_fixture(user)}
      end

    {:ok, session} = Ideation.create_session(actors.facilitator, project.id, %{title: "Character motivations"})
    Map.merge(actors, %{owner: user_scope_fixture(owner), project: project, session: session})
  end

  def idea_attrs(attrs \\ %{}) do
    Map.merge(%{request_key: Ecto.UUID.generate(), configuration_version: 1, body: "<p>Original idea</p>"}, attrs)
  end

  def idea_fixture(ctx, attrs \\ %{}, actor \\ nil) do
    {:ok, idea} = Ideation.create_idea(actor || ctx.author, ctx.project.id, ctx.session.id, idea_attrs(attrs))
    idea
  end

  def edit_attrs(attrs), do: Map.put_new(attrs, :request_key, Ecto.UUID.generate())

  def publish_idea(ctx, idea, actor \\ nil) do
    actor = actor || ctx.author

    {:ok, operation} =
      Ideation.prepare_idea_reveal(actor, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), [
        %{idea_id: idea.id, revision: idea.revision}
      ])

    {:ok, _} = Ideation.reveal_ideas(actor, ctx.project.id, ctx.session.id, operation.id)
    {:ok, result} = Ideation.get_idea(actor, ctx.project.id, ctx.session.id, idea.id)
    result
  end

  def configure_session(ctx, changes) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    {:ok, session} =
      Ideation.update_session(ctx.facilitator, ctx.project.id, current.id, current.revision, %{configuration: changes})

    %{ctx | session: session}
  end
end
