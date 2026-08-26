defmodule Storyarn.Scenes.Editor.Commands.Pins do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Commands.Positions
  alias Storyarn.Scenes.Editor.Commands.ReferenceIntegrity
  alias Storyarn.Scenes.Editor.Commands.Scenes
  alias Storyarn.Scenes.Editor.Commands.Shortcuts
  alias Storyarn.Scenes.References
  alias Storyarn.Scenes.ScenePin

  # A pin's shortcut is a referenceable variable, so create/update/delete change
  # the vocabulary every health surface type-checks against — not just the pin
  # count. Coordinates are also health inputs (`element_outside_canvas`), so the
  # optimized move path must participate in the same invalidation contract.
  def create_pin(scene_id, attrs) do
    attrs = enforce_leader_constraints(%ScenePin{scene_id: scene_id}, attrs)

    scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      pin = %ScenePin{scene_id: scene.id}

      with :ok <-
             Positions.lock_requested_layer_for_scene(scene.id, attrs),
           {:ok, attrs} <-
             ReferenceIntegrity.lock_pin_references(scene, pin, attrs) do
        attrs = maybe_generate_pin_shortcut(attrs, scene.id, nil)
        position = Positions.next_position(ScenePin, scene.id)
        ensure_single_leader(pin, attrs)

        pin
        |> ScenePin.create_changeset(Map.put(attrs, "position", position))
        |> persist_pin_with_references(scene.project_id)
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(scene_id)
  end

  def update_pin(%ScenePin{} = pin, attrs) do
    attrs = enforce_leader_constraints(pin, attrs)

    pin.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_pin} <- lock_pin_for_scene(pin.id, scene.id),
           :ok <-
             Positions.lock_requested_layer_for_scene(
               scene.id,
               attrs,
               locked_pin.layer_id
             ),
           {:ok, attrs} <-
             ReferenceIntegrity.lock_pin_references(
               scene,
               locked_pin,
               attrs
             ) do
        attrs = maybe_regenerate_pin_shortcut(locked_pin, attrs)
        ensure_single_leader(locked_pin, attrs)

        locked_pin
        |> ScenePin.update_changeset(attrs)
        |> persist_pin_with_references(scene.project_id)
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(pin.scene_id)
  end

  @doc """
  Moves a pin to a new position (position_x/position_y only — drag optimization).
  """
  def move_pin(%ScenePin{} = pin, position_x, position_y) do
    pin.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_pin} <- lock_pin_for_scene(pin.id, scene.id),
           {:ok, _attrs} <-
             ReferenceIntegrity.lock_pin_references(
               scene,
               locked_pin,
               %{}
             ),
           {:ok, updated_pin} <-
             locked_pin
             |> ScenePin.move_changeset(%{
               position_x: position_x,
               position_y: position_y
             })
             |> Repo.update() do
        {:ok, {updated_pin, scene.project_id}}
      end
    end)
    |> Scenes.broadcast_scene_dashboard_project_result()
  end

  def delete_pin(%ScenePin{} = pin) do
    pin.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_pin} <- lock_pin_for_scene(pin.id, scene.id),
           :ok <- delete_pin_references(locked_pin.id) do
        Repo.delete(locked_pin)
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(pin.scene_id)
  end

  def change_pin(%ScenePin{} = pin, attrs \\ %{}) do
    ScenePin.update_changeset(pin, attrs)
  end

  # When is_playable is set to false, force is_leader to false too
  defp enforce_leader_constraints(_pin, attrs) do
    attrs = MapUtils.stringify_keys(attrs)
    playable_value = attrs["is_playable"]

    if playable_value in [false, "false"] do
      Map.put(attrs, "is_leader", false)
    else
      attrs
    end
  end

  # When setting is_leader to true, clear is_leader on all other pins in the scene
  defp ensure_single_leader(pin, attrs) do
    leader_value = attrs["is_leader"] || attrs[:is_leader]

    if leader_value in [true, "true"] do
      demote_existing_leaders(pin)
    end
  end

  defp demote_existing_leaders(%ScenePin{id: nil, scene_id: scene_id}) do
    Repo.update_all(
      from(p in ScenePin, where: p.scene_id == ^scene_id and p.is_leader == true),
      set: [is_leader: false]
    )
  end

  defp demote_existing_leaders(%ScenePin{id: id, scene_id: scene_id}) do
    Repo.update_all(
      from(p in ScenePin, where: p.scene_id == ^scene_id and p.id != ^id and p.is_leader == true),
      set: [is_leader: false]
    )
  end

  # Generate shortcut from label on create if label present and no shortcut in attrs
  defp maybe_generate_pin_shortcut(attrs, scene_id, exclude_id) do
    label = attrs["label"]
    shortcut = attrs["shortcut"]

    if is_binary(label) && label != "" && is_nil(shortcut) do
      Map.put(attrs, "shortcut", Shortcuts.generate_pin(label, scene_id, exclude_id))
    else
      attrs
    end
  end

  # Regenerate shortcut on update when label changes
  # Note: attrs are already string-keyed from enforce_leader_constraints
  defp maybe_regenerate_pin_shortcut(pin, attrs) do
    new_label = attrs["label"]

    cond do
      label_being_cleared?(attrs, new_label) ->
        Map.put(attrs, "shortcut", nil)

      label_changing?(new_label, pin.label) ->
        Map.put(
          attrs,
          "shortcut",
          Shortcuts.generate_pin(new_label, pin.scene_id, pin.id)
        )

      shortcut_missing_for_existing_label?(pin, attrs) ->
        Map.put(
          attrs,
          "shortcut",
          Shortcuts.generate_pin(pin.label, pin.scene_id, pin.id)
        )

      true ->
        attrs
    end
  end

  defp label_being_cleared?(attrs, new_label), do: Map.has_key?(attrs, "label") and (is_nil(new_label) or new_label == "")

  defp label_changing?(new_label, current_label),
    do: is_binary(new_label) and new_label != "" and new_label != current_label

  defp shortcut_missing_for_existing_label?(pin, attrs),
    do: is_nil(pin.shortcut) and is_binary(pin.label) and pin.label != "" and not Map.has_key?(attrs, "label")

  defp lock_pin_for_scene(pin_id, scene_id) do
    case Repo.one(
           from(pin in ScenePin,
             where: pin.id == ^pin_id and pin.scene_id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %ScenePin{} = pin -> {:ok, pin}
      nil -> {:error, :pin_not_found}
    end
  end

  defp persist_pin_with_references(changeset, project_id) do
    with {:ok, pin} <- Repo.insert_or_update(changeset),
         :ok <-
           References.update_pin_entity_references(
             pin,
             project_id: project_id
           ),
         :ok <-
           References.update_pin_variable_references(
             pin,
             project_id: project_id
           ) do
      {:ok, pin}
    end
  end

  defp delete_pin_references(pin_id) do
    with {count, nil} when is_integer(count) <-
           References.delete_pin_entity_references(pin_id),
         :ok <- References.delete_pin_variable_references(pin_id) do
      :ok
    else
      result -> {:error, {:pin_reference_delete_failed, pin_id, result}}
    end
  end
end
