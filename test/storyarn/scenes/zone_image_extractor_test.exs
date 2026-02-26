defmodule Storyarn.Scenes.ZoneImageExtractorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.ZoneImageExtractor

  # =============================================================================
  # bounding_box/1
  # =============================================================================

  describe "bounding_box/1" do
    test "returns {0, 0, 0, 0} for empty list" do
      assert ZoneImageExtractor.bounding_box([]) == {0, 0, 0, 0}
    end

    test "computes bbox from string-keyed vertices" do
      vertices = [
        %{"x" => 10.0, "y" => 20.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 60.0}
      ]

      assert ZoneImageExtractor.bounding_box(vertices) == {10.0, 10.0, 50.0, 60.0}
    end

    test "computes bbox from atom-keyed vertices" do
      vertices = [
        %{x: 5.0, y: 15.0},
        %{x: 40.0, y: 5.0},
        %{x: 25.0, y: 45.0}
      ]

      assert ZoneImageExtractor.bounding_box(vertices) == {5.0, 5.0, 40.0, 45.0}
    end

    test "handles single vertex" do
      vertices = [%{"x" => 25.0, "y" => 75.0}]
      assert ZoneImageExtractor.bounding_box(vertices) == {25.0, 75.0, 25.0, 75.0}
    end

    test "handles vertices at extremes (0 and 100)" do
      vertices = [
        %{"x" => 0.0, "y" => 0.0},
        %{"x" => 100.0, "y" => 100.0}
      ]

      assert ZoneImageExtractor.bounding_box(vertices) == {0.0, 0.0, 100.0, 100.0}
    end

    test "all vertices at same point returns zero-size bbox" do
      vertices = [
        %{"x" => 50.0, "y" => 50.0},
        %{"x" => 50.0, "y" => 50.0},
        %{"x" => 50.0, "y" => 50.0}
      ]

      assert ZoneImageExtractor.bounding_box(vertices) == {50.0, 50.0, 50.0, 50.0}
    end

    test "handles integer coordinates" do
      vertices = [
        %{"x" => 10, "y" => 20},
        %{"x" => 50, "y" => 60}
      ]

      assert ZoneImageExtractor.bounding_box(vertices) == {10, 20, 50, 60}
    end
  end

  # =============================================================================
  # access_coord/2
  # =============================================================================

  describe "access_coord/2" do
    test "reads x from string-keyed map" do
      assert ZoneImageExtractor.access_coord(%{"x" => 42.5}, "x") == 42.5
    end

    test "reads y from string-keyed map" do
      assert ZoneImageExtractor.access_coord(%{"y" => 18.0}, "y") == 18.0
    end

    test "reads x from atom-keyed map" do
      assert ZoneImageExtractor.access_coord(%{x: 99.0}, "x") == 99.0
    end

    test "reads y from atom-keyed map" do
      assert ZoneImageExtractor.access_coord(%{y: 1.5}, "y") == 1.5
    end

    test "works with integer values" do
      assert ZoneImageExtractor.access_coord(%{"x" => 0}, "x") == 0
      assert ZoneImageExtractor.access_coord(%{y: 100}, "y") == 100
    end
  end

  # =============================================================================
  # normalize_vertices_to_bbox/1
  # =============================================================================

  describe "normalize_vertices_to_bbox/1" do
    test "returns nil for fewer than 3 vertices" do
      assert ZoneImageExtractor.normalize_vertices_to_bbox([]) == nil

      assert ZoneImageExtractor.normalize_vertices_to_bbox([
               %{"x" => 10.0, "y" => 10.0}
             ]) == nil

      assert ZoneImageExtractor.normalize_vertices_to_bbox([
               %{"x" => 10.0, "y" => 10.0},
               %{"x" => 50.0, "y" => 50.0}
             ]) == nil
    end

    test "normalizes a triangle spanning part of the canvas to 0-100 range" do
      # Triangle: (20, 10), (80, 10), (50, 70)
      # BBox: min_x=20, min_y=10, max_x=80, max_y=70
      # Range: x=60, y=60
      vertices = [
        %{"x" => 20.0, "y" => 10.0},
        %{"x" => 80.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 70.0}
      ]

      result = ZoneImageExtractor.normalize_vertices_to_bbox(vertices)
      assert is_list(result)
      assert length(result) == 3

      [v1, v2, v3] = result

      # (20-20)/60 * 100 = 0.0
      assert_in_delta v1.x, 0.0, 0.01
      # (10-10)/60 * 100 = 0.0
      assert_in_delta v1.y, 0.0, 0.01

      # (80-20)/60 * 100 = 100.0
      assert_in_delta v2.x, 100.0, 0.01
      # (10-10)/60 * 100 = 0.0
      assert_in_delta v2.y, 0.0, 0.01

      # (50-20)/60 * 100 = 50.0
      assert_in_delta v3.x, 50.0, 0.01
      # (70-10)/60 * 100 = 100.0
      assert_in_delta v3.y, 100.0, 0.01
    end

    test "normalizes atom-keyed vertices" do
      vertices = [
        %{x: 0.0, y: 0.0},
        %{x: 100.0, y: 0.0},
        %{x: 100.0, y: 100.0}
      ]

      result = ZoneImageExtractor.normalize_vertices_to_bbox(vertices)
      assert is_list(result)

      [v1, v2, v3] = result
      assert_in_delta v1.x, 0.0, 0.01
      assert_in_delta v1.y, 0.0, 0.01
      assert_in_delta v2.x, 100.0, 0.01
      assert_in_delta v2.y, 0.0, 0.01
      assert_in_delta v3.x, 100.0, 0.01
      assert_in_delta v3.y, 100.0, 0.01
    end

    test "returns nil when all vertices share the same x (zero x-range)" do
      vertices = [
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 30.0},
        %{"x" => 50.0, "y" => 60.0}
      ]

      assert ZoneImageExtractor.normalize_vertices_to_bbox(vertices) == nil
    end

    test "returns nil when all vertices share the same y (zero y-range)" do
      vertices = [
        %{"x" => 10.0, "y" => 50.0},
        %{"x" => 30.0, "y" => 50.0},
        %{"x" => 60.0, "y" => 50.0}
      ]

      assert ZoneImageExtractor.normalize_vertices_to_bbox(vertices) == nil
    end

    test "returns nil when all vertices are at the same point (zero both ranges)" do
      vertices = [
        %{"x" => 50.0, "y" => 50.0},
        %{"x" => 50.0, "y" => 50.0},
        %{"x" => 50.0, "y" => 50.0}
      ]

      assert ZoneImageExtractor.normalize_vertices_to_bbox(vertices) == nil
    end

    test "normalizes a square region correctly" do
      # Square from (10,10) to (60,60) = 50x50 range
      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 60.0, "y" => 10.0},
        %{"x" => 60.0, "y" => 60.0},
        %{"x" => 10.0, "y" => 60.0}
      ]

      result = ZoneImageExtractor.normalize_vertices_to_bbox(vertices)
      assert length(result) == 4

      # All corners should map to 0 or 100
      [v1, v2, v3, v4] = result
      assert_in_delta v1.x, 0.0, 0.01
      assert_in_delta v1.y, 0.0, 0.01
      assert_in_delta v2.x, 100.0, 0.01
      assert_in_delta v2.y, 0.0, 0.01
      assert_in_delta v3.x, 100.0, 0.01
      assert_in_delta v3.y, 100.0, 0.01
      assert_in_delta v4.x, 0.0, 0.01
      assert_in_delta v4.y, 100.0, 0.01
    end

    test "normalizes a small region with correct proportions" do
      # Vertices at (30,40), (40,40), (35,50)
      # BBox: min_x=30, min_y=40, max_x=40, max_y=50
      # Range: x=10, y=10
      vertices = [
        %{"x" => 30.0, "y" => 40.0},
        %{"x" => 40.0, "y" => 40.0},
        %{"x" => 35.0, "y" => 50.0}
      ]

      result = ZoneImageExtractor.normalize_vertices_to_bbox(vertices)
      [v1, v2, v3] = result

      assert_in_delta v1.x, 0.0, 0.01
      assert_in_delta v1.y, 0.0, 0.01
      assert_in_delta v2.x, 100.0, 0.01
      assert_in_delta v2.y, 0.0, 0.01
      # (35-30)/10 * 100 = 50.0
      assert_in_delta v3.x, 50.0, 0.01
      assert_in_delta v3.y, 100.0, 0.01
    end

    test "result uses atom keys" do
      vertices = [
        %{"x" => 10.0, "y" => 20.0},
        %{"x" => 50.0, "y" => 20.0},
        %{"x" => 30.0, "y" => 60.0}
      ]

      result = ZoneImageExtractor.normalize_vertices_to_bbox(vertices)
      first = hd(result)
      assert Map.has_key?(first, :x)
      assert Map.has_key?(first, :y)
      refute Map.has_key?(first, "x")
      refute Map.has_key?(first, "y")
    end
  end

  # NOTE: extract/3 error paths live in zone_image_extractor_integration_test.exs
end
