defmodule Storyarn.Assets.ImageOptimizationTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.ImageProcessor

  @test_image_path "test/fixtures/images/test_image.jpg"
  @test_png_path "test/fixtures/images/quadrant_map.png"

  # ── needs_optimization?/3 ──────────────────────────────────────

  describe "needs_optimization?/3 — avatar" do
    test "skips small JPEG avatar" do
      assert :skip ==
               ImageProcessor.needs_optimization?(
                 "image/jpeg",
                 %{"width" => 100, "height" => 100},
                 :avatar
               )
    end

    test "skips small WebP avatar" do
      assert :skip ==
               ImageProcessor.needs_optimization?(
                 "image/webp",
                 %{"width" => 192, "height" => 192},
                 :avatar
               )
    end

    test "generates for PNG avatar" do
      assert {:generate, %{width: 192, height: 192, crop: true}} =
               ImageProcessor.needs_optimization?(
                 "image/png",
                 %{"width" => 100, "height" => 100},
                 :avatar
               )
    end

    test "generates for oversized JPEG avatar" do
      assert {:generate, %{width: 192, height: 192, crop: true}} =
               ImageProcessor.needs_optimization?(
                 "image/jpeg",
                 %{"width" => 500, "height" => 500},
                 :avatar
               )
    end

    test "skips JPEG avatar with missing metadata (defaults to 0x0)" do
      assert :skip == ImageProcessor.needs_optimization?("image/jpeg", %{}, :avatar)
    end

    test "generates for GIF avatar regardless of size" do
      assert {:generate, %{width: 192, height: 192, crop: true}} =
               ImageProcessor.needs_optimization?(
                 "image/gif",
                 %{"width" => 50, "height" => 50},
                 :avatar
               )
    end
  end

  describe "needs_optimization?/3 — banner" do
    test "skips small JPEG banner" do
      assert :skip ==
               ImageProcessor.needs_optimization?(
                 "image/jpeg",
                 %{"width" => 1920, "height" => 640},
                 :banner
               )
    end

    test "generates for PNG banner" do
      assert {:generate, %{width: 1920, height: 640, crop: true}} =
               ImageProcessor.needs_optimization?(
                 "image/png",
                 %{"width" => 1920, "height" => 640},
                 :banner
               )
    end

    test "generates for oversized JPEG banner" do
      assert {:generate, %{width: 1920, height: 640, crop: true}} =
               ImageProcessor.needs_optimization?(
                 "image/jpeg",
                 %{"width" => 4000, "height" => 2000},
                 :banner
               )
    end
  end

  describe "needs_optimization?/3 — scene_background" do
    test "skips JPEG scene background" do
      assert :skip ==
               ImageProcessor.needs_optimization?(
                 "image/jpeg",
                 %{"width" => 4000, "height" => 3000},
                 :scene_background
               )
    end

    test "skips WebP scene background" do
      assert :skip ==
               ImageProcessor.needs_optimization?(
                 "image/webp",
                 %{"width" => 4000, "height" => 3000},
                 :scene_background
               )
    end

    test "generates for PNG scene background" do
      assert {:generate, %{crop: false}} =
               ImageProcessor.needs_optimization?(
                 "image/png",
                 %{"width" => 4000, "height" => 3000},
                 :scene_background
               )
    end

    test "generates for GIF scene background" do
      assert {:generate, %{crop: false}} =
               ImageProcessor.needs_optimization?("image/gif", %{}, :scene_background)
    end
  end

  describe "needs_optimization?/3 — gallery" do
    test "skips JPEG gallery image" do
      assert :skip == ImageProcessor.needs_optimization?("image/jpeg", %{}, :gallery)
    end

    test "generates for PNG gallery image" do
      assert {:generate, %{crop: false}} =
               ImageProcessor.needs_optimization?("image/png", %{}, :gallery)
    end
  end

  describe "needs_optimization?/3 — unknown purpose" do
    test "skips unknown purpose" do
      assert :skip == ImageProcessor.needs_optimization?("image/png", %{}, :unknown)
    end
  end

  # ── to_webp/1 ──────────────────────────────────────────────────

  describe "to_webp/1" do
    test "converts JPEG binary to WebP" do
      binary = File.read!(@test_image_path)

      assert {:ok, webp_data} = ImageProcessor.to_webp(binary)
      assert is_binary(webp_data)
      assert byte_size(webp_data) > 0
      # WebP magic bytes: RIFF....WEBP
      assert <<_riff::binary-size(4), _size::binary-size(4), "WEBP", _rest::binary>> = webp_data
    end

    test "converts PNG binary to WebP" do
      binary = File.read!(@test_png_path)

      assert {:ok, webp_data} = ImageProcessor.to_webp(binary)
      assert <<_riff::binary-size(4), _size::binary-size(4), "WEBP", _rest::binary>> = webp_data
    end

    test "returns error for invalid binary" do
      assert {:error, _reason} = ImageProcessor.to_webp("not an image")
    end

    test "cleans up temp files" do
      binary = File.read!(@test_image_path)
      tmp_dir = System.tmp_dir!()

      before_files = File.ls!(tmp_dir) |> Enum.filter(&String.starts_with?(&1, "storyarn_"))

      {:ok, _} = ImageProcessor.to_webp(binary)

      after_files = File.ls!(tmp_dir) |> Enum.filter(&String.starts_with?(&1, "storyarn_"))
      assert length(after_files) == length(before_files)
    end
  end

  # ── resize_to_webp/3 ──────────────────────────────────────────

  describe "resize_to_webp/3" do
    test "resizes and crops to exact dimensions" do
      binary = File.read!(@test_image_path)

      assert {:ok, webp_data} = ImageProcessor.resize_to_webp(binary, 50, 50)
      assert is_binary(webp_data)

      # Verify it's WebP
      assert <<_riff::binary-size(4), _size::binary-size(4), "WEBP", _rest::binary>> = webp_data

      # Write to temp and verify dimensions
      tmp = Path.join(System.tmp_dir!(), "resize_test_#{Ecto.UUID.generate()}.webp")

      try do
        File.write!(tmp, webp_data)
        assert {:ok, %{width: 50, height: 50}} = ImageProcessor.get_dimensions(tmp)
      after
        File.rm(tmp)
      end
    end

    test "returns error for invalid binary" do
      assert {:error, _reason} = ImageProcessor.resize_to_webp("not an image", 100, 100)
    end

    test "cleans up temp files on error" do
      tmp_dir = System.tmp_dir!()
      before_files = File.ls!(tmp_dir) |> Enum.filter(&String.starts_with?(&1, "storyarn_"))

      {:error, _} = ImageProcessor.resize_to_webp("not an image", 100, 100)

      after_files = File.ls!(tmp_dir) |> Enum.filter(&String.starts_with?(&1, "storyarn_"))
      assert length(after_files) == length(before_files)
    end
  end
end
