defmodule Storyarn.Notifications.Notification do
  @moduledoc """
  A durable in-app notification for one recipient.

  Notification rows store stable product codes and a small entity identity.
  User-facing copy and URLs are resolved later by the web layer so access can
  be rechecked and copy can be localized at render time.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Notifications.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Project

  @kinds ~w(async_operation content_created content_deleted)
  @entity_types ~w(
    project_snapshot
    workspace_snapshot_import
    project_import
    template_install
    localization_batch
    sheet
    flow
    scene
    localization_language
  )
  @statuses ~w(success failure)
  @project_scoped_entity_types ~w(
    project_snapshot
    project_import
    localization_batch
    sheet
    flow
    scene
    localization_language
  )

  @type t :: %__MODULE__{
          id: integer() | nil,
          recipient_id: integer() | nil,
          recipient: User.t() | NotLoaded.t() | nil,
          actor_id: integer() | nil,
          actor: User.t() | NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | NotLoaded.t() | nil,
          kind: String.t() | nil,
          entity_type: String.t() | nil,
          entity_id: integer() | nil,
          entity_name: String.t() | nil,
          status: String.t() | nil,
          dedupe_key: String.t() | nil,
          read_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "notifications" do
    field :kind, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :entity_name, :string
    field :status, :string
    field :dedupe_key, :string
    field :read_at, :utc_datetime

    belongs_to :recipient, User
    belongs_to :actor, User
    belongs_to :project, Project

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def create_changeset(notification, attrs) do
    notification
    |> cast(attrs, [:kind, :entity_type, :entity_id, :entity_name, :status, :dedupe_key])
    |> validate_required([:recipient_id, :kind, :dedupe_key])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:entity_type, @entity_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:entity_id, greater_than: 0)
    |> validate_length(:kind, max: 64)
    |> validate_length(:entity_type, max: 64)
    |> validate_length(:entity_name, max: 255)
    |> validate_length(:status, max: 32)
    |> validate_length(:dedupe_key, min: 1, max: 200)
    |> validate_entity_identity()
    |> validate_project_scope()
    |> validate_async_status()
    |> foreign_key_constraint(:recipient_id)
    |> foreign_key_constraint(:actor_id)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:recipient_id, :dedupe_key],
      name: :notifications_recipient_dedupe_index
    )
    |> check_constraint(:actor_id, name: :notifications_actor_recipient_check)
    |> check_constraint(:entity_type, name: :notifications_entity_identity_check)
    |> check_constraint(:project_id, name: :notifications_project_scope_check)
    |> check_constraint(:status, name: :notifications_status_check)
    |> check_constraint(:kind, name: :notifications_kind_not_blank)
    |> check_constraint(:dedupe_key, name: :notifications_dedupe_key_not_blank)
  end

  @doc false
  def kinds, do: @kinds

  @doc false
  def entity_types, do: @entity_types

  @doc false
  def statuses, do: @statuses

  defp validate_entity_identity(changeset) do
    entity_type = get_field(changeset, :entity_type)
    entity_id = get_field(changeset, :entity_id)

    if (is_nil(entity_type) and is_nil(entity_id)) or
         (is_binary(entity_type) and is_integer(entity_id)) do
      changeset
    else
      add_error(changeset, :entity_type, "must be provided together with entity_id")
    end
  end

  defp validate_async_status(changeset) do
    kind = get_field(changeset, :kind)
    status = get_field(changeset, :status)

    cond do
      kind == "async_operation" and is_nil(status) ->
        add_error(changeset, :status, "is required for asynchronous operations")

      kind in ["content_created", "content_deleted"] and not is_nil(status) ->
        add_error(changeset, :status, "is only valid for asynchronous operations")

      true ->
        changeset
    end
  end

  defp validate_project_scope(changeset) do
    entity_type = get_field(changeset, :entity_type)
    project_id = get_field(changeset, :project_id)

    if entity_type in @project_scoped_entity_types and is_nil(project_id) do
      add_error(changeset, :project_id, "is required for this entity type")
    else
      changeset
    end
  end
end
