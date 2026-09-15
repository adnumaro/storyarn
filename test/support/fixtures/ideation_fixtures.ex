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

  # Every session starts with its first round in progress.
  def first_round(ctx) do
    {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    round
  end

  # Starts the next round (closing the one in progress) and returns it with the
  # session at its new revision.
  def new_round(ctx, attrs \\ %{}) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, session} = Ideation.new_round(ctx.facilitator, ctx.project.id, current.id, current.revision, attrs)
    {:ok, %{active_round: round}} = Ideation.get_round_context(ctx.facilitator, ctx.project.id, current.id)
    {%{ctx | session: session}, round}
  end

  def close_round(ctx, round) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, session} = Ideation.close_round(ctx.facilitator, ctx.project.id, current.id, round.id, current.revision)
    %{ctx | session: session}
  end

  # Session-wide private mode became round privacy. Enabling hides the round in
  # progress; disabling reveals the round in progress, or the last one when
  # every round is closed. Callers keep the old five-argument shape.
  def set_private_mode(scope, project_id, session_id, revision, enabled, opts \\ []) do
    with {:ok, rounds} <- Ideation.list_rounds(scope, project_id, session_id) do
      round = Enum.find(rounds, &(&1.status == :active)) || List.first(rounds)
      reveal_on_expiry = Keyword.get(opts, :reveal_on_expiry, false)

      cond do
        is_nil(round) ->
          {:error, :round_required}

        enabled ->
          Ideation.set_round_privacy(scope, project_id, session_id, round.id, revision, %{
            private: true,
            reveal_on_expiry: reveal_on_expiry
          })

        true ->
          Ideation.reveal_round(scope, project_id, session_id, round.id, revision)
      end
    end
  end

  # Whether any round of the session currently hides other people's notes.
  def private_round?(scope, project_id, session_id) do
    {:ok, rounds} = Ideation.list_rounds(scope, project_id, session_id)
    Enum.any?(rounds, & &1.private)
  end

  def configure_session(ctx, changes) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    {:ok, session} =
      Ideation.update_session(ctx.facilitator, ctx.project.id, current.id, current.revision, %{configuration: changes})

    %{ctx | session: session}
  end
end
