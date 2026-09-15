defmodule Storyarn.Ideation.Sessions.Execution.RoundPrivacy do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # Ideas holds the contribution/session lock and owns the surrounding
  # transaction; publishing what a reveal makes visible is its job. Only the
  # round in progress changes, and a revealed round never goes private again.
  def set(access, expected, round_id, attrs) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :contribution_transaction_required}

      not (access.owner? or access.facilitator_id == access.user_id) ->
        {:error, :unauthorized}

      expected != access.session_revision ->
        {:error, :stale_revision}

      true ->
        with {:ok, round} <- RoundMutation.get(access.session_id, round_id), do: change_privacy(access, round, attrs)
    end
  end

  def active_private_round(session_id) do
    Repo.one(from r in Round, where: r.session_id == ^session_id and r.status == :active and r.private)
  end

  def private?(round_id) when is_integer(round_id),
    do: Repo.exists?(from r in Round, where: r.id == ^round_id and r.private)

  def private?(_round_id), do: false

  # Archiving freezes publication: end every private mask without revealing.
  # Returns how many rounds stopped hiding, so the archive can wake the sources.
  # Archiving ends every mask for good: the round counts as revealed, without
  # publishing anything, so reopening cannot hide it again.
  def end_masks(session_id) do
    now = %{TimeHelpers.now() | microsecond: {0, 6}}

    {count, _} =
      Repo.update_all(from(r in Round, where: r.session_id == ^session_id and r.private),
        set: [private: false, revealed_at: now]
      )

    count
  end

  defp change_privacy(access, round, attrs) do
    changeset = Round.privacy_changeset(round, attrs)
    private = get_change(changeset, :private)

    cond do
      not changeset.valid? -> {:error, :invalid_privacy}
      round.status == :closed and private != false -> {:error, :round_not_active}
      private == true and not is_nil(round.revealed_at) -> {:error, :round_revealed}
      changeset.changes == %{} -> {:ok, %{id: round.id, round: round, changed: false, revealed: false}}
      true -> persist(access, round, changeset, private == false)
    end
  end

  defp persist(access, round, changeset, revealed) do
    now = %{TimeHelpers.now() | microsecond: {0, 6}}
    changeset = if revealed, do: put_change(changeset, :revealed_at, now), else: changeset

    with {:ok, updated} <- Repo.update(changeset),
         session = Repo.get!(Session, access.session_id),
         {:ok, _} <- RoundMutation.record(session, access, updated, :round_updated) do
      {:ok, %{id: round.id, round: updated, changed: true, revealed: revealed}}
    end
  end
end
