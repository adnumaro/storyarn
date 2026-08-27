defmodule Storyarn.Flows.Versioning.Projections.UserRecord do
  @moduledoc """
  Versioning-owned user projection for version authors and localization audit identities.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
  end
end
