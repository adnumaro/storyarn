defmodule Storyarn.Imports.PlanStorageTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.Storage
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Vault

  test "a plan without source_kind roundtrips as a canonical file import" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(nil))
    assert {:ok, %ImportPlan{source_kind: :file}} = PlanStorage.load(key)
  end

  test "archive source_kind roundtrips unchanged" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(:archive))
    assert {:ok, %ImportPlan{source_kind: :archive}} = PlanStorage.load(key)
  end

  test "loads the empty source_kind emitted by the previous encoder" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    legacy_payload = %{
      "format" => "yarn",
      "parser_version" => "3",
      "source_kind" => "",
      "data" => %{}
    }

    encrypted =
      legacy_payload
      |> Jason.encode!()
      |> :zlib.gzip()
      |> then(fn compressed ->
        assert {:ok, encrypted} = Vault.encrypt(compressed)
        encrypted
      end)

    assert {:ok, _private_url} = Storage.upload(key, encrypted, "application/octet-stream")
    assert {:ok, %ImportPlan{source_kind: :file}} = PlanStorage.load(key)
  end

  test "rejects an unknown source_kind before uploading a plan" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:error, :import_plan_storage_failed} = PlanStorage.store_at(key, plan(:directory))
    assert {:error, _reason} = Storage.download(key)
  end

  defp plan(source_kind) do
    %ImportPlan{
      format: :yarn,
      parser_version: "3",
      source_kind: source_kind,
      data: %{}
    }
  end

  defp storage_key do
    "imports/plans/#{Ecto.UUID.generate()}.plan.enc"
  end
end
