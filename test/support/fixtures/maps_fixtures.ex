defmodule Storyarn.MapsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Maps` context.
  """

  alias Storyarn.Maps
  alias Storyarn.ProjectsFixtures

  def unique_map_name, do: "Map #{System.unique_integer([:positive])}"

  def valid_map_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_map_name(),
      description: "A test map"
    })
  end

  @doc """
  Creates a map.
  """
  def map_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, map} =
      attrs
      |> valid_map_attributes()
      |> then(&Maps.create_map(project, &1))

    map
  end

  @doc """
  Creates a layer within a map.
  """
  def layer_fixture(map, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "name" => "Layer #{System.unique_integer([:positive])}"
      })

    {:ok, layer} = Maps.create_layer(map.id, attrs)
    layer
  end

  @doc """
  Creates a zone within a map.
  """
  def zone_fixture(map, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "name" => "Zone #{System.unique_integer([:positive])}",
        "vertices" => [
          %{"x" => 10.0, "y" => 10.0},
          %{"x" => 50.0, "y" => 10.0},
          %{"x" => 30.0, "y" => 50.0}
        ]
      })

    {:ok, zone} = Maps.create_zone(map.id, attrs)
    zone
  end

  @doc """
  Creates a pin within a map.
  """
  def pin_fixture(map, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "position_x" => 50.0,
        "position_y" => 50.0,
        "label" => "Pin #{System.unique_integer([:positive])}"
      })

    {:ok, pin} = Maps.create_pin(map.id, attrs)
    pin
  end

  @doc """
  Creates an annotation within a map.
  """
  def annotation_fixture(map, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "text" => "Note #{System.unique_integer([:positive])}",
        "position_x" => 50.0,
        "position_y" => 50.0
      })

    {:ok, annotation} = Maps.create_annotation(map.id, attrs)
    annotation
  end

  @doc """
  Creates a connection between two pins within a map.
  """
  def connection_fixture(map, from_pin, to_pin, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "from_pin_id" => from_pin.id,
        "to_pin_id" => to_pin.id
      })

    {:ok, connection} = Maps.create_connection(map.id, attrs)
    connection
  end
end
