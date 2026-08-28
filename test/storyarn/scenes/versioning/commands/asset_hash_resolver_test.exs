defmodule Storyarn.Scenes.Versioning.Commands.AssetHashResolverTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Versioning.Commands.AssetHashResolver

  test "accepts a valid Scene image catalog entry" do
    hash = String.duplicate("a", 64)

    metadata = %{
      "filename" => "scene.png",
      "content_type" => "image/png",
      "size" => 123,
      "project_id" => 42
    }

    assert {:ok, 42} =
             AssetHashResolver.validate_portable_catalog_entry(
               hash,
               metadata,
               42,
               expected_content_type_prefix: "image/"
             )
  end

  test "rejects a portable catalog entry outside the Scene image contract" do
    hash = String.duplicate("b", 64)

    metadata = %{
      "filename" => "scene.html",
      "content_type" => "text/html",
      "size" => 123,
      "project_id" => 42
    }

    assert {:error, :invalid_asset_content_type} =
             AssetHashResolver.validate_portable_catalog_entry(
               hash,
               metadata,
               42,
               expected_content_type_prefix: "image/"
             )
  end

  test "preserves the portable SVG source-key restriction" do
    hash = String.duplicate("c", 64)

    metadata = %{
      "filename" => "scene.svg",
      "content_type" => "image/svg+xml",
      "sanitized_svg" => true,
      "size" => 123,
      "project_id" => 42
    }

    assert {:error, :unsupported_portable_svg} =
             AssetHashResolver.validate_portable_catalog_entry(
               hash,
               metadata,
               42,
               expected_content_type_prefix: "image/",
               asset_source_keys: %{hash => "trusted/scene.svg"}
             )
  end
end
