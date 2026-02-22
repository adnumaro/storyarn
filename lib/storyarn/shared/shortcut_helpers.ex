defmodule Storyarn.Shared.ShortcutHelpers do
  @moduledoc """
  Shared helpers for shortcut generation across CRUD modules.

  Extracts common patterns from flow_crud, sheet_crud, map_crud, and screenplay_crud
  while keeping context-specific logic (update-path regeneration with backlink checks)
  in each CRUD module.
  """

  @doc """
  Auto-generates shortcut from name on create if not already provided.

  `generator_fn` is called as `generator_fn.(name, project_id, exclude_id)`.
  """
  @spec maybe_generate_shortcut(map(), integer(), integer() | nil, function()) :: map()
  def maybe_generate_shortcut(attrs, project_id, exclude_id, generator_fn) do
    has_shortcut = Map.has_key?(attrs, "shortcut")
    name = attrs["name"]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = generator_fn.(name, project_id, exclude_id)
      Map.put(attrs, "shortcut", shortcut)
    end
  end

  @doc """
  Returns true if attrs contain a new, non-empty name different from the entity's current name.
  """
  @spec name_changing?(map(), struct()) :: boolean()
  def name_changing?(attrs, entity) do
    new_name = attrs["name"]
    new_name && new_name != "" && new_name != entity.name
  end

  @doc """
  Returns true if the entity's shortcut is nil or empty.
  """
  @spec missing_shortcut?(struct()) :: boolean()
  def missing_shortcut?(entity) do
    is_nil(entity.shortcut) || entity.shortcut == ""
  end

  @doc """
  Generates shortcut from the entity's current name when shortcut is missing.
  Used as a fallback in update paths.

  `generator_fn` is called as `generator_fn.(name, project_id, entity_id)`.
  """
  @spec generate_shortcut_from_name(struct(), map(), function()) :: map()
  def generate_shortcut_from_name(entity, attrs, generator_fn) do
    name = entity.name

    if name && name != "" do
      shortcut = generator_fn.(name, entity.project_id, entity.id)
      Map.put(attrs, "shortcut", shortcut)
    else
      attrs
    end
  end

  @doc """
  Auto-assigns position if not provided in attrs.

  `position_fn` is called as `position_fn.(project_id, parent_id)`.
  """
  @spec maybe_assign_position(map(), integer(), integer() | nil, function()) :: map()
  def maybe_assign_position(attrs, project_id, parent_id, position_fn) do
    if Map.has_key?(attrs, "position") do
      attrs
    else
      position = position_fn.(project_id, parent_id)
      Map.put(attrs, "position", position)
    end
  end
end
