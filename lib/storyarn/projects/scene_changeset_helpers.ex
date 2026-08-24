defmodule Storyarn.Projects.SceneChangesetHelpers do
  @moduledoc false

  import Ecto.Changeset

  alias Storyarn.Platform.Shared.TimeHelpers

  @color_regex ~r/\A#[0-9a-fA-F]{3}([0-9a-fA-F]{3}([0-9a-fA-F]{2})?)?\z/
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

  def validate_target_pair(changeset, valid_types) do
    changeset
    |> validate_target_type_inclusion(valid_types)
    |> validate_target_pair_presence()
  end

  def validate_color(changeset, field) do
    validate_format(changeset, field, @color_regex, message: "must be a valid hex color (#RGB, #RRGGBB, or #RRGGBBAA)")
  end

  defp validate_target_type_inclusion(changeset, valid_types) do
    case get_field(changeset, :target_type) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :target_type, valid_types)
    end
  end

  defp validate_target_pair_presence(changeset) do
    case {get_field(changeset, :target_type), get_field(changeset, :target_id)} do
      {nil, nil} -> changeset
      {nil, _target_id} -> add_error(changeset, :target_type, "is required when target_id is set")
      {_target_type, nil} -> add_error(changeset, :target_id, "is required when target_type is set")
      {_target_type, _target_id} -> changeset
    end
  end
end
