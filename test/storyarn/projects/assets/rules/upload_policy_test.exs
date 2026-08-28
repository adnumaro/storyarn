defmodule Storyarn.Projects.Assets.UploadPolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets.UploadPolicy

  test "request size is derived from the shared compile-time HTTP limit" do
    limits = Application.fetch_env!(:storyarn, :project_asset_upload_limits)

    assert UploadPolicy.max_file_size() == Keyword.fetch!(limits, :max_image_size)

    assert UploadPolicy.max_request_size() ==
             Keyword.fetch!(limits, :max_image_size) +
               Keyword.fetch!(limits, :multipart_request_overhead)
  end

  describe "validate_base64_size/2" do
    test "accepts the maximum encoded size for the profile" do
      profile = %{max_file_size: 3}

      assert :ok = UploadPolicy.validate_base64_size(profile, "AAAA")
    end

    test "rejects encoded data larger than the profile before decoding" do
      profile = %{max_file_size: 3}

      assert {:error, :too_large} = UploadPolicy.validate_base64_size(profile, "AAAAA")
    end

    test "rounds the Base64 boundary up for partial groups" do
      profile = %{max_file_size: 4}

      assert :ok = UploadPolicy.validate_base64_size(profile, "AAAAAAAA")
      assert {:error, :too_large} = UploadPolicy.validate_base64_size(profile, "AAAAAAAAA")
    end
  end
end
