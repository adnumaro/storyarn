defmodule Storyarn.AI.Alerts do
  @moduledoc false

  alias Storyarn.AI.OperatorAlert
  alias Storyarn.Repo

  def record(attrs) when is_map(attrs) do
    %OperatorAlert{}
    |> OperatorAlert.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: :dedupe_key
    )
  end
end
