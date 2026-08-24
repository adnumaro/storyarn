defmodule Storyarn.AI.Persistence.UserRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end
end

defimpl FunWithFlags.Actor, for: Storyarn.AI.Persistence.UserRecord do
  @moduledoc """
  Mirrors the `Storyarn.Accounts.User` actor identity for the AI-owned user
  record so feature-flag targeting resolves to the same `user:{id}` actor.
  """
  def id(%Storyarn.AI.Persistence.UserRecord{id: id}), do: "user:#{id}"
end
