defmodule Storyarn.Shared.HierarchicalSchema do
  @moduledoc """
  Shared changeset helpers for hierarchical entities (sheets, flows, scenes, screenplays).

  Eliminates duplication of standard soft-delete, restore, move, and validation functions
  that are identical across all four main entity schemas.

  ## Usage

      alias Storyarn.Shared.HierarchicalSchema

      def delete_changeset(entity), do: HierarchicalSchema.delete_changeset(entity)
      def restore_changeset(entity), do: HierarchicalSchema.restore_changeset(entity)
      def move_changeset(entity, attrs), do: HierarchicalSchema.move_changeset(entity, attrs)
      def deleted?(entity), do: HierarchicalSchema.deleted?(entity)
  """

  import Ecto.Changeset
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Creates a changeset that sets `deleted_at` to the current time.
  """
  def delete_changeset(entity) do
    change(entity, %{deleted_at: TimeHelpers.now()})
  end

  @doc """
  Creates a changeset that clears `deleted_at`.
  """
  def restore_changeset(entity) do
    change(entity, %{deleted_at: nil})
  end

  @doc """
  Creates a changeset for parent_id + position updates (tree moves).
  """
  def move_changeset(entity, attrs) do
    entity
    |> cast(attrs, [:parent_id, :position])
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Returns true if the entity has been soft-deleted.
  """
  def deleted?(%{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  @doc """
  Validates core name fields common to all hierarchical entities.

  Validates name is required and between 1-200 characters.
  """
  def validate_core_fields(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end

  @doc """
  Validates the optional description field (max 2000 characters).
  """
  def validate_description(changeset) do
    validate_length(changeset, :description, max: 2000)
  end
end
