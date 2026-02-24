defmodule Storyarn.Shared.ShortcutHelpers do
  @moduledoc """
  Shared helpers for shortcut generation across CRUD modules.

  Extracts common patterns from flow_crud, sheet_crud, scene_crud, and screenplay_crud
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
  Handles shortcut regeneration on update.

  `generator_fn` is called as `generator_fn.(name, project_id, entity_id)`.

  ## Options

    * `:check_backlinks_fn` - When provided, called as `check_backlinks_fn.(entity)`.
      Must return a boolean. When true and the entity is referenced, the shortcut is
      preserved (not regenerated) to avoid breaking existing references.
  """
  def maybe_generate_shortcut_on_update(entity, attrs, generator_fn, opts \\ []) do
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)
    check_backlinks_fn = Keyword.get(opts, :check_backlinks_fn)

    cond do
      Map.has_key?(attrs, "shortcut") ->
        attrs

      name_changing?(attrs, entity) ->
        if check_backlinks_fn do
          regenerate_with_backlink_check(entity, attrs, generator_fn, check_backlinks_fn)
        else
          shortcut = generator_fn.(attrs["name"], entity.project_id, entity.id)
          Map.put(attrs, "shortcut", shortcut)
        end

      missing_shortcut?(entity) ->
        generate_shortcut_from_name(entity, attrs, generator_fn)

      true ->
        attrs
    end
  end

  defp regenerate_with_backlink_check(entity, attrs, generator_fn, check_backlinks_fn) do
    referenced? = check_backlinks_fn.(entity)

    shortcut =
      Storyarn.Shared.NameNormalizer.maybe_regenerate(
        entity.shortcut,
        attrs["name"],
        referenced?,
        &Storyarn.Shared.NameNormalizer.shortcutify/1
      )

    shortcut =
      if shortcut != entity.shortcut do
        generator_fn.(attrs["name"], entity.project_id, entity.id)
      else
        shortcut
      end

    Map.put(attrs, "shortcut", shortcut)
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
