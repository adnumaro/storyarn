defmodule Storyarn.Ideation.Ideas.Commands.BringForward do
  @moduledoc false
  import Ecto.Query, only: [where: 3]
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.Revisions
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Band
  alias Storyarn.Ideation.Ideas.Rules.Canvas
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  # "Bring to the active round" is the only way an idea crosses rounds: a new note of
  # the actor's own under the header in progress, linked to the revision of the
  # original they can read. The original stays where it was, in its state.
  def run(scope, project_id, session_id, source_id, attrs) when valid_id(source_id) and is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs) do
      Transaction.run(scope, project_id, session_id, &bring_locked(&1, key, source_id, attrs))
    end
  end

  def run(_scope, _project_id, _session_id, _source_id, _attrs), do: {:error, :invalid_idea}

  defp bring_locked(access, key, source_id, attrs) do
    fingerprint = Input.fingerprint({:bring, source_id, Input.get(attrs, :canvas)})

    case Repo.get_by(Idea, session_id: access.session_id, author_id: access.user_id, creation_key: key) do
      nil ->
        insert(access, key, fingerprint, source_id, attrs)

      idea ->
        edit = Repo.get_by!(Edit, idea_id: idea.id, actor_id: access.user_id, request_key: key)
        Revisions.replay(edit, fingerprint, idea, access.user_id)
    end
  end

  defp insert(access, key, fingerprint, source_id, attrs) do
    with :ok <- contributions_open(access),
         {:ok, source, revision} <- readable(access, source_id),
         {:ok, round} <- Sessions.select_contribution_round(access, :active),
         :ok <- crosses_round(source, round),
         {:ok, policy} <- Policy.contribution_policy(access, %{canvas_contribution: true}, round.private),
         {:ok, canvas} <- Canvas.normalize(placement(source.canvas, Input.get(attrs, :canvas))),
         :ok <- Band.check(canvas) do
      idea =
        Repo.insert!(
          struct!(
            Idea,
            %{
              canvas: canvas,
              session_id: access.session_id,
              round_id: round.round_id,
              late_contribution: round.late_contribution,
              author_id: access.user_id,
              author_kind: :human,
              creation_key: key,
              state: :active,
              publication_consent: policy.consent,
              configuration_version: access.configuration_version,
              creation_source_id: source.id,
              source_idea_id: source.id,
              source_revision: revision.number
            }
          )
        )

      content = %Revision{title: revision.title, body: revision.body, state: :active}
      copy = Revisions.insert(idea, content, access.user_id)
      Revisions.record_edit(idea, access, key, fingerprint, 0, :saved)
      idea = if policy.shared?, do: Publication.publish_creation(idea, access.user_id), else: idea

      Transaction.success(
        View.idea(idea, copy, access.user_id, not is_nil(source.published_revision)),
        audiences(access, policy, round, source)
      )
    end
  end

  # A parked original leaves the "For later" count once it has a copy ahead.
  defp audiences(access, policy, round, source) do
    readers = if policy.shared? or round.private, do: [:shared], else: [access.user_id]
    if source.state == :parked, do: [:tree | readers], else: readers
  end

  defp contributions_open(%{contributions_open: true}), do: :ok
  defp contributions_open(_access), do: {:error, :contributions_closed}

  defp readable(access, source_id) do
    case access.session_id |> Visible.query(access.user_id) |> where([i], i.id == ^source_id) |> Repo.one() do
      {source, revision, _provenance_published?} -> {:ok, source, revision}
      nil -> {:error, :not_found}
    end
  end

  defp crosses_round(%{round_id: round_id}, %{round_id: round_id}), do: {:error, :same_round}
  defp crosses_round(_source, _round), do: :ok

  # The copy keeps the original's look; the caller places it inside the band.
  defp placement(source, nil), do: placement(source, %{})

  defp placement(source, attrs) when is_map(attrs) do
    source
    |> Map.take(~w(width color shape))
    |> Map.merge(%{"x" => Map.get(source, "x", 0), "y" => 0})
    |> Map.merge(attrs |> MapAccess.stringify_keys() |> Map.take(~w(x y)))
  end

  defp placement(_source, _attrs), do: %{}
end
