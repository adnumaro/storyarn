defmodule Storyarn.Projects.Imports.FlowQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Repo

  @spec get_active_main_identity(integer()) :: nil | %{shortcut: String.t() | nil}
  def get_active_main_identity(project_id) do
    Repo.one(
      from(flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.is_main == true and
            is_nil(flow.deleted_at),
        select: %{shortcut: flow.shortcut}
      )
    )
  end
end
