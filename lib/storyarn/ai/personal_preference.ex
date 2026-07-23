defmodule Storyarn.AI.PersonalPreference do
  @moduledoc """
  Actor-owned primary provider/model preference for one role in one workspace.

  This table deliberately models only the primary choice. Ordered alternatives
  can be introduced later as child records without weakening the primary
  identity of `{user, workspace, role}`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Integration
  alias Storyarn.Workspaces.Workspace

  @type t :: %__MODULE__{}

  schema "ai_personal_preferences" do
    field :slot, :string
    field :provider, :string
    field :model, :string

    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :integration, Integration

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(%__MODULE__{} = preference, attrs) do
    preference
    |> change(attrs)
    |> common_validations()
    |> unique_constraint([:user_id, :workspace_id, :slot],
      name: :ai_personal_preferences_user_workspace_slot_index
    )
  end

  @doc false
  def update_route_changeset(%__MODULE__{} = preference, attrs) do
    preference
    |> change(Map.take(attrs, [:integration_id, :provider, :model]))
    |> common_validations()
  end

  defp common_validations(changeset) do
    changeset
    |> validate_required([:user_id, :workspace_id, :integration_id, :slot, :provider, :model])
    |> validate_inclusion(:slot, ~w(general_assistant writing_assistant illustrator voice))
    |> validate_length(:provider, min: 1, max: 100)
    |> validate_length(:model, min: 1, max: 255)
    |> check_constraint(:slot, name: :ai_personal_preferences_slot_allowed)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:integration_id)
  end
end
