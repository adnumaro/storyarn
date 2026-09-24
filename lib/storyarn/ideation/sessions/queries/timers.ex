defmodule Storyarn.Ideation.Sessions.Queries.Timers do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  def get(scope, project_id, session_id) do
    with {:ok, session} <- Get.run(scope, project_id, session_id) do
      {:ok, in_progress(session.id)}
    end
  end

  # The clock of the round in progress; a closed round keeps its clock as history.
  def in_progress(session_id) do
    Repo.one(
      from t in Timer,
        join: r in Round,
        on: r.id == t.round_id,
        where: t.session_id == ^session_id and r.status == :active
    )
  end

  def scheduled do
    Repo.all(
      from t in Timer,
        join: s in Session,
        on: s.id == t.session_id,
        where: t.status == :running and is_nil(s.deleted_at) and s.status == :open,
        order_by: [asc: t.deadline_at, asc: t.id],
        select: map(t, [:id, :version, :deadline_at])
    )
  end
end
