defmodule Storyarn.Assets.ImageProcessorExtendedTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.ImageProcessor

  @test_image_path "test/fixtures/images/test_image.jpg"
  @test_output_dir "test/tmp/image_processor_ext"

  setup do
    File.mkdir_p!(@test_output_dir)
    on_exit(fn -> File.rm_rf!(@test_output_dir) end)
    :ok
  end

  # ── Error handling ──────────────────────────────────────────────

  describe "generate_thumbnail/2 error handling" do
    test "returns error for non-existent source" do
      assert {:error, msg} = ImageProcessor.generate_thumbnail("/nonexistent.jpg")
      assert is_binary(msg)
    end

    test "returns error for non-image file" do
      path = Path.join(@test_output_dir, "text.txt")
      File.write!(path, "not an image")
      assert {:error, _} = ImageProcessor.generate_thumbnail(path)
    end
  end

  describe "resize/2 error handling" do
    test "returns error for non-existent source" do
      assert {:error, msg} = ImageProcessor.resize("/nonexistent.jpg")
      assert is_binary(msg)
    end

    test "returns error for non-image file" do
      path = Path.join(@test_output_dir, "text.txt")
      File.write!(path, "not an image")
      assert {:error, _} = ImageProcessor.resize(path)
    end

    test "copies to output path when no resize needed" do
      output = Path.join(@test_output_dir, "copied.jpg")

      assert {:ok, ^output} =
               ImageProcessor.resize(@test_image_path,
                 max_width: 10_000,
                 max_height: 10_000,
                 output_path: output
               )

      assert File.exists?(output)
    end

    test "in-place resize when output_path equals source" do
      # Copy test image to temp so we can resize in-place
      temp = Path.join(@test_output_dir, "inplace.jpg")
      File.cp!(@test_image_path, temp)

      # max_width/max_height larger than image — should be a no-op copy
      assert {:ok, ^temp} = ImageProcessor.resize(temp, max_width: 10_000, max_height: 10_000)
      assert File.exists?(temp)
    end
  end

  describe "optimize/2 error handling" do
    test "returns error for non-existent source" do
      assert {:error, _} = ImageProcessor.optimize("/nonexistent.jpg")
    end

    test "optimizes with custom quality" do
      output = Path.join(@test_output_dir, "quality.jpg")

      assert {:ok, ^output} =
               ImageProcessor.optimize(@test_image_path, output_path: output, quality: 50)

      assert File.exists?(output)
    end
  end

  describe "process_image/2 error handling" do
    test "returns error for non-existent source" do
      assert {:error, _} = ImageProcessor.process_image("/nonexistent.jpg")
    end

    test "generates thumbnail with explicit output path" do
      source = Path.join(@test_output_dir, "auto_test.jpg")
      File.cp!(@test_image_path, source)
      thumb = Path.join(@test_output_dir, "auto_test_thumb.jpg")

      assert {:ok, result} = ImageProcessor.process_image(source, thumbnail_output: thumb)
      assert result.thumbnail_path == thumb
      assert File.exists?(result.thumbnail_path)
    end

    test "metadata contains width, height and thumbnail_path" do
      thumb = Path.join(@test_output_dir, "meta_thumb.jpg")

      assert {:ok, result} =
               ImageProcessor.process_image(@test_image_path, thumbnail_output: thumb)

      assert result.metadata["width"] == 100
      assert result.metadata["height"] == 50
      assert result.metadata["thumbnail_path"] == thumb
    end
  end

  describe "generate_thumbnail/2 auto-path" do
    test "generates thumbnail_path from source_path when not specified" do
      source = Path.join(@test_output_dir, "source.jpg")
      File.cp!(@test_image_path, source)

      assert {:ok, path} = ImageProcessor.generate_thumbnail(source)
      assert path == Path.join(@test_output_dir, "source_thumb.jpg")
      assert File.exists?(path)
    end
  end

  describe "resize/2 dimension verification" do
    test "respects max_width constraint" do
      output = Path.join(@test_output_dir, "width_constraint.jpg")

      assert {:ok, _} =
               ImageProcessor.resize(@test_image_path,
                 max_width: 30,
                 max_height: 1000,
                 output_path: output
               )

      {:ok, %{width: w}} = ImageProcessor.get_dimensions(output)
      assert w <= 30
    end

    test "respects max_height constraint" do
      output = Path.join(@test_output_dir, "height_constraint.jpg")

      assert {:ok, _} =
               ImageProcessor.resize(@test_image_path,
                 max_width: 1000,
                 max_height: 20,
                 output_path: output
               )

      {:ok, %{height: h}} = ImageProcessor.get_dimensions(output)
      assert h <= 20
    end
  end
end
