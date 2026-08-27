defmodule Storyarn.AI.Governance.Projections.UserRecord do
  @moduledoc "Governance-owned projection of user identity for policy attribution and reauthorization."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end
end
