defmodule Storyarn.Scenes.ConnectionCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Scenes.ConnectionCrud

  import Storyarn.AccountsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  defp create_scene_with_pins(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)
    pin_a = pin_fixture(scene, %{"label" => "Pin A"})
    pin_b = pin_fixture(scene, %{"label" => "Pin B"})
    %{project: project, scene: scene, pin_a: pin_a, pin_b: pin_b}
  end

  # =============================================================================
  # create_connection/2
  # =============================================================================

  describe "create_connection/2" do
    test "creates a connection between two pins" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()

      assert {:ok, connection} =
               ConnectionCrud.create_connection(scene.id, %{
                 "from_pin_id" => pin_a.id,
                 "to_pin_id" => pin_b.id
               })

      assert connection.from_pin_id == pin_a.id
      assert connection.to_pin_id == pin_b.id
      assert connection.scene_id == scene.id
    end
  end

  # =============================================================================
  # list_connections/1
  # =============================================================================

  describe "list_connections/1" do
    test "returns empty list when no connections" do
      %{scene: scene} = create_scene_with_pins()
      assert ConnectionCrud.list_connections(scene.id) == []
    end

    test "returns connections for a scene" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()
      connection_fixture(scene, pin_a, pin_b)

      connections = ConnectionCrud.list_connections(scene.id)
      assert length(connections) == 1
    end
  end

  # =============================================================================
  # get_connection/2
  # =============================================================================

  describe "get_connection/2" do
    test "returns connection by id scoped to scene" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()
      connection = connection_fixture(scene, pin_a, pin_b)

      assert result = ConnectionCrud.get_connection(scene.id, connection.id)
      assert result.id == connection.id
    end

    test "returns nil for non-existent connection" do
      %{scene: scene} = create_scene_with_pins()
      assert ConnectionCrud.get_connection(scene.id, -1) == nil
    end
  end

  # =============================================================================
  # update_connection/2
  # =============================================================================

  describe "update_connection/2" do
    test "updates connection attributes" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()
      connection = connection_fixture(scene, pin_a, pin_b)

      assert {:ok, updated} =
               ConnectionCrud.update_connection(connection, %{
                 "label" => "New Label"
               })

      assert updated.label == "New Label"
    end
  end

  # =============================================================================
  # update_connection_waypoints/2
  # =============================================================================

  describe "update_connection_waypoints/2" do
    test "updates waypoints" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()
      connection = connection_fixture(scene, pin_a, pin_b)

      waypoints = [%{"x" => 10.0, "y" => 20.0}, %{"x" => 30.0, "y" => 40.0}]

      assert {:ok, updated} =
               ConnectionCrud.update_connection_waypoints(connection, %{"waypoints" => waypoints})

      assert updated.waypoints == waypoints
    end
  end

  # =============================================================================
  # delete_connection/1
  # =============================================================================

  describe "delete_connection/1" do
    test "deletes a connection" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()
      connection = connection_fixture(scene, pin_a, pin_b)

      assert {:ok, _deleted} = ConnectionCrud.delete_connection(connection)
      assert ConnectionCrud.get_connection(scene.id, connection.id) == nil
    end
  end

  # =============================================================================
  # change_connection/2
  # =============================================================================

  describe "change_connection/2" do
    test "returns a changeset for tracking" do
      %{scene: scene, pin_a: pin_a, pin_b: pin_b} = create_scene_with_pins()
      connection = connection_fixture(scene, pin_a, pin_b)

      changeset = ConnectionCrud.change_connection(connection, %{})
      assert %Ecto.Changeset{} = changeset
    end
  end
end
