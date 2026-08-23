defmodule Storyarn.Sheets.Persistence.WorkspaceMembershipRecord do
  @moduledoc false

  use Ecto.Schema

  schema "workspace_memberships" do
    field :workspace_id, :id
    field :user_id, :id
    field :role, :string

    timestamps(type: :utc_datetime)
  end
end
