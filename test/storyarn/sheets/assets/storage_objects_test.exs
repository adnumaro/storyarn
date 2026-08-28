defmodule Storyarn.Sheets.Assets.Adapters.Storage.ObjectsTest do
  use ExUnit.Case, async: false

  alias Storyarn.ConditionalCopyStorageSpy
  alias Storyarn.Sheets.Assets.Adapters.Storage.Objects

  @blob_copy_key "projects/42/blobs/.storyarn-copy/AbCdEfGhIjKlMnOp"
  @asset_uuid "a1b2c3d4-e5f6-47a8-9b0c-d1e2f3a4b5c6"
  @asset_copy_key "projects/42/assets/#{@asset_uuid}/.storyarn-copy/QrStUvWxYz012345"

  setup do
    original_storage = Application.get_env(:storyarn, :storage, [])

    Application.put_env(:storyarn, :storage, adapter: ConditionalCopyStorageSpy)
    ConditionalCopyStorageSpy.configure()

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)
  end

  test "fails closed for invalid, recoverable, and non-owned keys" do
    recoverable_key = "projects/42/blobs/#{String.duplicate("a", 64)}.png"
    malformed_copy_key = "projects/42/assets/#{@asset_uuid}/.storyarn-copy/too-short"

    assert {:error, :invalid_key} =
             Objects.delete_owned_conditional_copy("projects/42/../unsafe")

    assert {:error, :recoverable_blob} =
             Objects.delete_owned_conditional_copy(recoverable_key)

    assert {:error, :conditional_copy_not_owned} =
             Objects.delete_owned_conditional_copy(malformed_copy_key)

    refute_received {:conditional_copy_delete, _key}
  end

  test "accepts only the two Sheets-owned conditional-copy key shapes" do
    for key <- [@blob_copy_key, @asset_copy_key] do
      assert :ok = Objects.delete_owned_conditional_copy(key)
      assert_receive {:conditional_copy_delete, ^key}
    end
  end

  test "propagates a provider delete failure" do
    ConditionalCopyStorageSpy.configure(delete_result: {:error, :delete_failed})

    assert {:error, :delete_failed} = Objects.delete_owned_conditional_copy(@blob_copy_key)
    assert_receive {:conditional_copy_delete, @blob_copy_key}
  end
end
