defmodule Storyarn.Scenes.Editor.Rules.Schema do
  @moduledoc false

  import Ecto.Changeset

  alias Storyarn.Platform.Shared.TimeHelpers

  @shortcut_format ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/

  def delete_changeset(entity), do: change(entity, %{deleted_at: TimeHelpers.now()})
  def restore_changeset(entity), do: change(entity, %{deleted_at: nil})

  def move_changeset(entity, attrs) do
    entity
    |> cast(attrs, [:parent_id, :position])
    |> foreign_key_constraint(:parent_id)
  end

  def deleted?(%{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  def validate_core_fields(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end

  def validate_description(changeset), do: validate_length(changeset, :description, max: 2_000)

  def validate_shortcut(changeset, opts \\ []) do
    message = Keyword.get(opts, :message, "must be lowercase, alphanumeric, with dots or hyphens")

    changeset
    |> validate_length(:shortcut, min: 1, max: 50)
    |> validate_format(:shortcut, @shortcut_format, message: message)
  end
end
