defmodule Storyarn.Scenes.ChangesetHelpers do
  @moduledoc """
  Shared changeset helpers for scene element schemas.
  """

  import Ecto.Changeset

  @color_regex ~r/\A#[0-9a-fA-F]{3}([0-9a-fA-F]{3}([0-9a-fA-F]{2})?)?\z/

  @doc """
  Validates that target_type and target_id are set or unset together.
  Validates that target_type, if set, is one of valid_types.
  """
  def validate_target_pair(changeset, valid_types) do
    changeset
    |> validate_target_type_inclusion(valid_types)
    |> validate_target_pair_presence()
  end

  defp validate_target_type_inclusion(changeset, valid_types) do
    case get_field(changeset, :target_type) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :target_type, valid_types)
    end
  end

  defp validate_target_pair_presence(changeset) do
    target_type = get_field(changeset, :target_type)
    target_id = get_field(changeset, :target_id)
    check_target_pair(changeset, target_type, target_id)
  end

  defp check_target_pair(changeset, nil, nil), do: changeset

  defp check_target_pair(changeset, nil, _target_id) do
    add_error(changeset, :target_type, "is required when target_id is set")
  end

  defp check_target_pair(changeset, _target_type, nil) do
    add_error(changeset, :target_id, "is required when target_type is set")
  end

  defp check_target_pair(changeset, _target_type, _target_id), do: changeset

  @doc "Validates that a color field is a valid hex CSS color (#RGB, #RRGGBB, or #RRGGBBAA)."
  def validate_color(changeset, field) do
    validate_format(changeset, field, @color_regex,
      message: "must be a valid hex color (#RGB, #RRGGBB, or #RRGGBBAA)"
    )
  end
end
