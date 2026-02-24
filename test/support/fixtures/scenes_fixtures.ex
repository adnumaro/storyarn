defmodule Storyarn.ScenesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Scenes` context.
  """

  alias Storyarn.ProjectsFixtures
  alias Storyarn.Scenes

  def unique_scene_name, do: "Scene #{System.unique_integer([:positive])}"

  def valid_scene_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_scene_name(),
      description: "A test scene"
    })
  end

  @doc """
  Creates a scene.
  """
  def scene_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, scene} =
      attrs
      |> valid_scene_attributes()
      |> then(&Scenes.create_scene(project, &1))

    scene
  end

  @doc """
  Creates a layer within a scene.
  """
  def layer_fixture(scene, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "name" => "Layer #{System.unique_integer([:positive])}"
      })

    {:ok, layer} = Scenes.create_layer(scene.id, attrs)
    layer
  end

  @doc """
  Creates a zone within a scene.
  """
  def zone_fixture(scene, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "name" => "Zone #{System.unique_integer([:positive])}",
        "vertices" => [
          %{"x" => 10.0, "y" => 10.0},
          %{"x" => 50.0, "y" => 10.0},
          %{"x" => 30.0, "y" => 50.0}
        ]
      })

    {:ok, zone} = Scenes.create_zone(scene.id, attrs)
    zone
  end

  @doc """
  Creates a pin within a scene.
  """
  def pin_fixture(scene, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "position_x" => 50.0,
        "position_y" => 50.0,
        "label" => "Pin #{System.unique_integer([:positive])}"
      })

    {:ok, pin} = Scenes.create_pin(scene.id, attrs)
    pin
  end

  @doc """
  Creates an annotation within a scene.
  """
  def annotation_fixture(scene, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "text" => "Note #{System.unique_integer([:positive])}",
        "position_x" => 50.0,
        "position_y" => 50.0
      })

    {:ok, annotation} = Scenes.create_annotation(scene.id, attrs)
    annotation
  end

  @doc """
  Creates a connection between two pins within a scene.
  """
  def connection_fixture(scene, from_pin, to_pin, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "from_pin_id" => from_pin.id,
        "to_pin_id" => to_pin.id
      })

    {:ok, connection} = Scenes.create_connection(scene.id, attrs)
    connection
  end
end
