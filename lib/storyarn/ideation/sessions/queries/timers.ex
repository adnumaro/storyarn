defmodule Storyarn.Ideation.Sessions.Queries.Timers do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  def get(scope, project_id, session_id) do
    with {:ok, session} <- Get.run(scope, project_id, session_id) do
      {:ok, Repo.get_by(Timer, session_id: session.id)}
    end
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
