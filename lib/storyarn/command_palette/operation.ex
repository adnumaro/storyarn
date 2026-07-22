defmodule Storyarn.CommandPalette.Operation do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User

  @events ~w(palette_create palette_delete)

  schema "command_palette_operations" do
    field :event, :string
    field :operation_id, :string
    field :result, :map

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def events, do: @events

  def changeset(operation, attrs) do
    operation
    |> cast(attrs, [:event, :operation_id, :result])
    |> validate_required([:user_id, :event, :operation_id, :result])
    |> validate_inclusion(:event, @events)
    |> validate_length(:operation_id, min: 1, max: 64)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :event, :operation_id],
      name: :command_palette_operations_actor_event_id_unique
    )
    |> check_constraint(:event, name: :command_palette_operations_event_check)
    |> check_constraint(:operation_id, name: :command_palette_operations_id_length_check)
    |> check_constraint(:result, name: :command_palette_operations_result_object_check)
  end
end
