defmodule Storyarn.Assets.ImageProcessorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.ImageProcessor

  @test_image_path "test/fixtures/images/test_image.jpg"
  @test_output_dir "test/tmp/image_processor"

  setup do
    File.mkdir_p!(@test_output_dir)
    on_exit(fn -> File.rm_rf!(@test_output_dir) end)
    :ok
  end

  describe "available?/0" do
    test "returns true when Image library is loaded" do
      assert ImageProcessor.available?() == true
    end
  end

  describe "get_dimensions/1" do
    test "returns dimensions for valid image" do
      assert {:ok, %{width: width, height: height}} =
               ImageProcessor.get_dimensions(@test_image_path)

      assert is_integer(width) and width > 0
      assert is_integer(height) and height > 0
      # Our test image is 100x50
      assert width == 100
      assert height == 50
    end

    test "returns error for non-existent file" do
      assert {:error, _} = ImageProcessor.get_dimensions("/nonexistent.jpg")
    end

    test "returns error for non-image file" do
      text_path = Path.join(@test_output_dir, "text.txt")
      File.write!(text_path, "not an image")
      assert {:error, _} = ImageProcessor.get_dimensions(text_path)
    end
  end

  describe "generate_thumbnail/2" do
    test "creates thumbnail with default size" do
      output = Path.join(@test_output_dir, "thumb.jpg")

      assert {:ok, ^output} =
               ImageProcessor.generate_thumbnail(@test_image_path, output_path: output)

      assert File.exists?(output)

      {:ok, %{width: w, height: h}} = ImageProcessor.get_dimensions(output)
      # Our test image is 100x50, smaller than default 200, so it shouldn't be resized
      assert w <= 200
      assert h <= 200
    end

    test "creates thumbnail with custom size" do
      output = Path.join(@test_output_dir, "thumb_small.jpg")

      assert {:ok, _} =
               ImageProcessor.generate_thumbnail(@test_image_path, output_path: output, size: 50)

      {:ok, %{width: w, height: h}} = ImageProcessor.get_dimensions(output)
      assert max(w, h) <= 50
    end
  end

  describe "resize/2" do
    test "resizes image to fit within bounds" do
      output = Path.join(@test_output_dir, "resized.jpg")

      assert {:ok, _} =
               ImageProcessor.resize(@test_image_path,
                 max_width: 50,
                 max_height: 50,
                 output_path: output
               )

      {:ok, %{width: w, height: h}} = ImageProcessor.get_dimensions(output)
      assert w <= 50 and h <= 50
    end

    test "does not upscale small images" do
      output = Path.join(@test_output_dir, "no_upscale.jpg")
      {:ok, orig} = ImageProcessor.get_dimensions(@test_image_path)

      assert {:ok, _} =
               ImageProcessor.resize(@test_image_path,
                 max_width: 10_000,
                 max_height: 10_000,
                 output_path: output
               )

      {:ok, new} = ImageProcessor.get_dimensions(output)
      assert new.width == orig.width and new.height == orig.height
    end
  end

  describe "optimize/2" do
    test "optimizes image" do
      output = Path.join(@test_output_dir, "optimized.jpg")
      assert {:ok, ^output} = ImageProcessor.optimize(@test_image_path, output_path: output)
      assert File.exists?(output)
    end
  end

  describe "process_image/2" do
    test "creates thumbnail and extracts metadata" do
      thumb = Path.join(@test_output_dir, "process_thumb.jpg")
      assert {:ok, result} = ImageProcessor.process_image(@test_image_path, thumbnail_output: thumb)

      assert result.thumbnail_path == thumb
      assert is_integer(result.metadata["width"])
      assert is_integer(result.metadata["height"])
      assert File.exists?(thumb)
    end
  end

  describe "backward compatibility" do
    test "imagemagick_available?/0 is deprecated but works" do
      # Should work but emit a deprecation warning in compilation
      assert ImageProcessor.imagemagick_available?() == ImageProcessor.available?()
    end
  end
end
