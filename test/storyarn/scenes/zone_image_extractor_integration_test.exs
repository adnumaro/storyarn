defmodule Storyarn.Scenes.ZoneImageExtractorIntegrationTest do
  @moduledoc """
  Integration + snapshot tests for ZoneImageExtractor.extract/3.

  ## Snapshot tests
  Reference images live in `test/fixtures/images/snapshots/`.
  Each test extracts a zone from the fantasy map, then compares
  the output against the committed snapshot (SHA-256 hash match).

  To regenerate snapshots after pipeline changes:
      mix run test/fixtures/images/generate_snapshots.exs

  ## Test images
  - `test_image.jpg` (100x50px) — generic pipeline / error tests
  - `quadrant_map.png` (400x200px) — crop correctness by color
  - `fantasy_map.jpg` (1024x1024px) — realistic snapshot tests

  ## Note on polygon shapes
  ZoneImageExtractor always crops via bounding_box/1 (rectangular crop).
  Different polygon shapes produce identical output when their bounding
  boxes match. Polygon rendering is a frontend concern (Leaflet canvas).
  The unit tests for bounding_box/1 already cover varied vertex counts.
  """
  # async: false — writes to shared priv/static/uploads/ and reads back
  # with libvips, which races under heavy parallel I/O (flaky :enoent)
  use Storyarn.DataCase, async: false

  alias Storyarn.Assets
  alias Storyarn.Scenes.{SceneZone, ZoneImageExtractor}

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  @test_image_path "test/fixtures/images/test_image.jpg"
  @quadrant_image_path "test/fixtures/images/quadrant_map.png"
  @fantasy_map_path "test/fixtures/images/fantasy_map.jpg"
  @snapshots_dir "test/fixtures/images/snapshots"

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup do
    user = user_fixture()
    project = project_fixture(user)

    image_data = File.read!(@test_image_path)
    key = Assets.generate_key(project, "background.jpg")
    {:ok, url} = Assets.storage_upload(key, image_data, "image/jpeg")

    {:ok, bg_asset} =
      Assets.create_asset(project, %{
        filename: "background.jpg",
        content_type: "image/jpeg",
        size: byte_size(image_data),
        key: key,
        url: url
      })

    parent_map = %{
      background_asset_id: bg_asset.id,
      background_asset: bg_asset
    }

    upload_dir = "priv/static/uploads/projects/#{project.id}"
    on_exit(fn -> File.rm_rf!(upload_dir) end)

    %{project: project, parent_map: parent_map, bg_asset: bg_asset, upload_dir: upload_dir}
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sha256(path) do
    :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
  end

  defp rect(x1, y1, x2, y2) do
    [
      %{"x" => x1, "y" => y1},
      %{"x" => x2, "y" => y1},
      %{"x" => x2, "y" => y2},
      %{"x" => x1, "y" => y2}
    ]
  end

  defp setup_fantasy_map(ctx) do
    image_data = File.read!(@fantasy_map_path)
    key = Assets.generate_key(ctx.project, "fantasy_map.jpg")
    {:ok, url} = Assets.storage_upload(key, image_data, "image/jpeg")

    {:ok, map_asset} =
      Assets.create_asset(ctx.project, %{
        filename: "fantasy_map.jpg",
        content_type: "image/jpeg",
        size: byte_size(image_data),
        key: key,
        url: url
      })

    %{
      map_parent: %{
        background_asset_id: map_asset.id,
        background_asset: map_asset
      }
    }
  end

  defp extract_and_compare!(ctx, zone_name, vertices) do
    zone = %SceneZone{name: zone_name, vertices: vertices}

    {:ok, asset, {w, h}} =
      ZoneImageExtractor.extract(ctx.map_parent, zone, ctx.project)

    actual_path = Path.join("priv/static", asset.url)
    snapshot_path = Path.join(@snapshots_dir, "#{zone_name}.webp")

    assert File.exists?(snapshot_path),
           "Snapshot not found: #{snapshot_path}. Run: mix run test/fixtures/images/generate_snapshots.exs"

    {:ok, snap_img} = Image.open(snapshot_path)
    snap_w = Image.width(snap_img)
    snap_h = Image.height(snap_img)

    assert {w, h} == {snap_w, snap_h},
           "Dimension mismatch for #{zone_name}: got #{w}x#{h}, snapshot #{snap_w}x#{snap_h}"

    actual_hash = sha256(actual_path)
    snapshot_hash = sha256(snapshot_path)

    assert actual_hash == snapshot_hash,
           "Snapshot mismatch for #{zone_name}.\n" <>
             "  Expected: #{String.slice(snapshot_hash, 0, 16)}...\n" <>
             "  Got:      #{String.slice(actual_hash, 0, 16)}...\n" <>
             "  Actual file: #{actual_path}\n" <>
             "  Regenerate: mix run test/fixtures/images/generate_snapshots.exs"

    {asset, {w, h}}
  end

  # ===========================================================================
  # Snapshot tests — fantasy map extractions
  # ===========================================================================

  describe "snapshot: fantasy map zone extractions" do
    setup ctx, do: setup_fantasy_map(ctx)

    test "strait_island matches snapshot", ctx do
      {_asset, {w, h}} = extract_and_compare!(ctx, "strait_island", rect(49.0, 36.0, 57.0, 44.0))
      assert {w, h} == {1000, 1000}
    end

    test "northwest_peninsula matches snapshot", ctx do
      {_asset, {w, h}} =
        extract_and_compare!(ctx, "northwest_peninsula", rect(5.0, 6.0, 33.0, 38.0))

      assert {w, h} == {875, 1000}
    end

    test "sw_island matches snapshot", ctx do
      {_asset, {w, h}} = extract_and_compare!(ctx, "sw_island", rect(4.0, 81.0, 16.0, 93.0))
      assert {w, h} == {1000, 1000}
    end

    test "waterfall_cove matches snapshot", ctx do
      {_asset, {w, h}} = extract_and_compare!(ctx, "waterfall_cove", rect(74.0, 22.0, 92.0, 38.0))
      assert {w, h} == {1000, 891}
    end

    test "south_forest matches snapshot", ctx do
      {_asset, {w, h}} = extract_and_compare!(ctx, "south_forest", rect(14.0, 53.0, 58.0, 82.0))
      assert {w, h} == {1000, 659}
    end

    test "panoramic_strait matches snapshot", ctx do
      {_asset, {w, h}} =
        extract_and_compare!(ctx, "panoramic_strait", rect(0.0, 28.0, 100.0, 48.0))

      assert {w, h} == {1024, 205}
    end

    test "river_valley matches snapshot", ctx do
      {_asset, {w, h}} = extract_and_compare!(ctx, "river_valley", rect(20.0, 40.0, 42.0, 68.0))
      assert {w, h} == {784, 1000}
    end

    test "tiny_detail matches snapshot", ctx do
      {_asset, {w, h}} = extract_and_compare!(ctx, "tiny_detail", rect(44.0, 64.0, 50.0, 70.0))
      assert {w, h} == {1000, 1000}
    end
  end

  # ===========================================================================
  # Pipeline tests — basic extract/3 behavior
  # ===========================================================================

  describe "extract/3 pipeline" do
    test "creates WebP asset with correct metadata", ctx do
      zone = %SceneZone{
        name: "Center Region",
        vertices: rect(20.0, 10.0, 80.0, 90.0)
      }

      assert {:ok, asset, {w, h}} =
               ZoneImageExtractor.extract(ctx.parent_map, zone, ctx.project)

      assert asset.id
      assert asset.content_type == "image/webp"
      assert asset.filename =~ ".webp"
      assert is_integer(w) and w > 0
      assert is_integer(h) and h > 0
      assert max(w, h) >= 1000
    end

    test "extracted file exists on disk and is valid WebP", ctx do
      zone = %SceneZone{name: "Disk Check", vertices: rect(10.0, 10.0, 60.0, 60.0)}

      {:ok, asset, {w, h}} = ZoneImageExtractor.extract(ctx.parent_map, zone, ctx.project)

      file_path = Path.join("priv/static", asset.url)
      assert File.exists?(file_path)
      assert File.stat!(file_path).size == asset.size

      {:ok, img} = Image.open(file_path)
      assert Image.width(img) == w
      assert Image.height(img) == h
    end

    test "creates unique assets for each extraction", ctx do
      zone1 = %SceneZone{name: "Zone A", vertices: rect(0.0, 0.0, 50.0, 50.0)}
      zone2 = %SceneZone{name: "Zone B", vertices: rect(50.0, 50.0, 100.0, 100.0)}

      {:ok, a1, _} = ZoneImageExtractor.extract(ctx.parent_map, zone1, ctx.project)
      {:ok, a2, _} = ZoneImageExtractor.extract(ctx.parent_map, zone2, ctx.project)

      assert a1.id != a2.id
      assert a1.key != a2.key
      assert a1.filename =~ "zone_a"
      assert a2.filename =~ "zone_b"
    end

    test "maintains aspect ratio in upscaled output", ctx do
      zone = %SceneZone{name: "Wide Zone", vertices: rect(10.0, 40.0, 90.0, 60.0)}

      {:ok, _asset, {w, h}} = ZoneImageExtractor.extract(ctx.parent_map, zone, ctx.project)

      assert w > h
      assert_in_delta w / h, 80.0 / 10.0, 1.0
    end

    test "sanitizes special characters in zone name", ctx do
      zone = %SceneZone{name: "Café / Bäckerei (Main)", vertices: rect(10.0, 10.0, 50.0, 50.0)}

      {:ok, asset, _} = ZoneImageExtractor.extract(ctx.parent_map, zone, ctx.project)
      refute asset.filename =~ "/"
      refute asset.filename =~ "("
      assert asset.filename =~ ".webp"
    end

    test "atom-keyed vertices work", ctx do
      zone = %SceneZone{
        name: "Atom Keys",
        vertices: [
          %{x: 20.0, y: 20.0},
          %{x: 80.0, y: 20.0},
          %{x: 80.0, y: 80.0},
          %{x: 20.0, y: 80.0}
        ]
      }

      assert {:ok, asset, {w, h}} =
               ZoneImageExtractor.extract(ctx.parent_map, zone, ctx.project)

      assert asset.id
      assert is_integer(w) and w > 0
      assert is_integer(h) and h > 0
    end
  end

  # ===========================================================================
  # Error paths
  # ===========================================================================

  describe "extract/3 errors" do
    test "nil background_asset_id", _ctx do
      zone = %SceneZone{name: "T", vertices: rect(10.0, 10.0, 90.0, 90.0)}

      assert {:error, :no_background_image} =
               ZoneImageExtractor.extract(%{background_asset_id: nil}, zone, %{})
    end

    test "unpreloaded background_asset_id", _ctx do
      zone = %SceneZone{name: "T", vertices: rect(10.0, 10.0, 90.0, 90.0)}

      assert {:error, :no_background_image} =
               ZoneImageExtractor.extract(%{background_asset_id: 999}, zone, %{})
    end

    @tag capture_log: true
    test "missing file on disk", ctx do
      parent = %{
        background_asset_id: ctx.bg_asset.id,
        background_asset: %{url: "/uploads/nonexistent.jpg"}
      }

      zone = %SceneZone{name: "T", vertices: rect(10.0, 10.0, 90.0, 90.0)}

      assert {:error, :image_extraction_failed} =
               ZoneImageExtractor.extract(parent, zone, ctx.project)
    end

    test "empty parent_map", _ctx do
      zone = %SceneZone{name: "T", vertices: rect(10.0, 10.0, 90.0, 90.0)}
      assert {:error, :no_background_image} = ZoneImageExtractor.extract(%{}, zone, %{})
    end
  end

  # ===========================================================================
  # Crop correctness — quadrant color verification
  # ===========================================================================

  describe "crop correctness (quadrant image)" do
    setup ctx do
      image_data = File.read!(@quadrant_image_path)
      key = Assets.generate_key(ctx.project, "quadrant_bg.png")
      {:ok, url} = Assets.storage_upload(key, image_data, "image/png")

      {:ok, quad_asset} =
        Assets.create_asset(ctx.project, %{
          filename: "quadrant_bg.png",
          content_type: "image/png",
          size: byte_size(image_data),
          key: key,
          url: url
        })

      %{quad_parent: %{background_asset_id: quad_asset.id, background_asset: quad_asset}}
    end

    test "top-left → red", ctx do
      zone = %SceneZone{name: "TL", vertices: rect(5.0, 5.0, 45.0, 45.0)}
      {:ok, asset, _} = ZoneImageExtractor.extract(ctx.quad_parent, zone, ctx.project)
      {:ok, img} = Image.open(Path.join("priv/static", asset.url))
      {:ok, [r, g, b | _]} = Image.dominant_color(img)
      assert r > 200 and g < 50 and b < 50, "Expected red, got [#{r},#{g},#{b}]"
    end

    test "top-right → green", ctx do
      zone = %SceneZone{name: "TR", vertices: rect(55.0, 5.0, 95.0, 45.0)}
      {:ok, asset, _} = ZoneImageExtractor.extract(ctx.quad_parent, zone, ctx.project)
      {:ok, img} = Image.open(Path.join("priv/static", asset.url))
      {:ok, [r, g, b | _]} = Image.dominant_color(img)
      assert g > 200 and r < 50 and b < 50, "Expected green, got [#{r},#{g},#{b}]"
    end

    test "bottom-left → blue", ctx do
      zone = %SceneZone{name: "BL", vertices: rect(5.0, 55.0, 45.0, 95.0)}
      {:ok, asset, _} = ZoneImageExtractor.extract(ctx.quad_parent, zone, ctx.project)
      {:ok, img} = Image.open(Path.join("priv/static", asset.url))
      {:ok, [r, g, b | _]} = Image.dominant_color(img)
      assert b > 200 and r < 50 and g < 50, "Expected blue, got [#{r},#{g},#{b}]"
    end

    test "bottom-right → yellow", ctx do
      zone = %SceneZone{name: "BR", vertices: rect(55.0, 55.0, 95.0, 95.0)}
      {:ok, asset, _} = ZoneImageExtractor.extract(ctx.quad_parent, zone, ctx.project)
      {:ok, img} = Image.open(Path.join("priv/static", asset.url))
      {:ok, [r, g, b | _]} = Image.dominant_color(img)
      assert r > 200 and g > 200 and b < 50, "Expected yellow, got [#{r},#{g},#{b}]"
    end
  end
end
