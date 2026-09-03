defmodule Storyarn.Projects.Imports.PlanStorageTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.PlanStorage

  @envelope_magic "STORYARN_IMPORT_PLAN"
  @envelope_version 1
  @binding_nonce_bytes 32
  @binding_digest_bytes 32
  @binding_domain "storyarn:import-plan:storage-key:v1"

  test "a plan without source_kind roundtrips as a canonical file import" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(nil))
    assert {:ok, %ImportPlan{source_kind: :file}} = PlanStorage.load(key)
  end

  test "load stops inflating the moment the size cap is crossed" do
    # The limit must be protective, not post-validation: with a plain gunzip
    # the whole binary materializes before any check can look at it.
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(:file))
    assert {:error, :import_plan_unavailable} = PlanStorage.load(key, max_json_bytes: 8)
    assert {:ok, %ImportPlan{}} = PlanStorage.load(key)
  end

  test "archive source_kind roundtrips unchanged" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(:archive))
    assert {:ok, %ImportPlan{source_kind: :archive}} = PlanStorage.load(key)
  end

  test "replacement eligibility stays ephemeral in a legacy parser-v5 payload" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    eligible = %{plan(:archive) | parser_version: "5", replace_eligible: true}
    additive_only = %{eligible | replace_eligible: false}

    assert {:ok, eligible_binding} = PlanStorage.canonical_binding_payload(eligible)
    assert {:ok, ^eligible_binding} = PlanStorage.canonical_binding_payload(additive_only)
    assert {:ok, ^key} = PlanStorage.store_at(key, eligible)
    assert {:ok, %ImportPlan{parser_version: "5", replace_eligible: nil}} = PlanStorage.load(key)

    refute key |> stored_payload() |> Map.has_key?("replace_eligible")
  end

  test "roundtrips only the privacy-safe issue aggregate" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    stored_plan = %{
      plan(:file)
      | metadata: %{
          warning_count: 3,
          error_count: 0,
          issue_count: 3,
          issues_truncated: false,
          issue_counts_by_code: %{"yarn_markup_preserved" => 1, unsupported_yarn_command: 2},
          filename: "private-client-project.yarn",
          source: "Alice: private dialogue"
        }
    }

    assert {:ok, ^key} = PlanStorage.store_at(key, stored_plan)
    assert {:ok, encrypted} = Storage.download(key)
    refute encrypted =~ "private-client-project.yarn"
    refute encrypted =~ "Alice: private dialogue"

    assert {:ok, loaded} = PlanStorage.load(key)

    assert loaded.metadata == %{
             warning_count: 3,
             error_count: 0,
             issue_count: 3,
             issues_truncated: false,
             issue_counts_by_code: %{
               "unsupported_yarn_command" => 2,
               "yarn_markup_preserved" => 1
             }
           }
  end

  test "loads a bound payload with the empty source_kind emitted by the previous encoder" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    legacy_payload = %{
      "format" => "yarn",
      "parser_version" => "3",
      "source_kind" => "",
      "data" => %{}
    }

    encrypted = encrypted_bound_payload(key, legacy_payload)

    assert {:ok, _private_url} = Storage.upload(key, encrypted, "application/octet-stream")
    assert {:ok, %ImportPlan{source_kind: :file}} = PlanStorage.load(key)
  end

  test "rejects ciphertext replayed under a different storage key" do
    source_key = storage_key()
    destination_key = storage_key()

    on_exit(fn ->
      PlanStorage.delete(source_key)
      PlanStorage.delete(destination_key)
    end)

    assert {:ok, ^source_key} = PlanStorage.store_at(source_key, plan(:file))
    assert {:ok, ciphertext} = Storage.download(source_key)
    assert {:ok, _private_url} = Storage.upload(destination_key, ciphertext, "application/octet-stream")

    assert {:ok, %ImportPlan{source_kind: :file}} = PlanStorage.load(source_key)
    assert {:error, :import_plan_unavailable} = PlanStorage.load(destination_key)
  end

  test "uses fresh authenticated nonces when overwriting the same key" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(:file))
    assert {:ok, first_ciphertext} = Storage.download(key)

    assert {:ok, ^key} = PlanStorage.store_at(key, plan(:file))
    assert {:ok, second_ciphertext} = Storage.download(key)

    refute first_ciphertext == second_ciphertext
    assert {:ok, %ImportPlan{source_kind: :file}} = PlanStorage.load(key)
  end

  test "rejects unbound legacy ciphertext instead of accepting a replayable object" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    encrypted =
      :file
      |> plan()
      |> encoded_payload()
      |> :zlib.gzip()
      |> then(fn compressed ->
        assert {:ok, encrypted} = Vault.encrypt(compressed)
        encrypted
      end)

    assert {:ok, _private_url} = Storage.upload(key, encrypted, "application/octet-stream")
    assert {:error, :import_plan_unavailable} = PlanStorage.load(key)
  end

  test "bounds JSON before compression and reports a safe permanent error" do
    exact_key = storage_key()
    oversized_key = storage_key()
    stored_plan = plan(:archive, %{"content" => String.duplicate("x", 512)})
    json_bytes = stored_plan |> encoded_payload() |> byte_size()

    on_exit(fn ->
      PlanStorage.delete(exact_key)
      PlanStorage.delete(oversized_key)
    end)

    assert {:ok, ^exact_key} =
             PlanStorage.store_at(exact_key, stored_plan, max_json_bytes: json_bytes)

    assert {:error, :import_plan_too_large} =
             PlanStorage.store_at(oversized_key, stored_plan, max_json_bytes: json_bytes - 1)

    assert {:error, _reason} = Storage.download(oversized_key)

    assert {"import_plan_too_large", "The import file could not be processed.", true} =
             Error.classify(:import_plan_too_large)
  end

  test "honors the configured JSON limit and allows a scoped override" do
    configured_key = storage_key()
    override_key = storage_key()
    stored_plan = plan(:file, %{"content" => String.duplicate("x", 256)})
    json_bytes = stored_plan |> encoded_payload() |> byte_size()
    original_config = Application.get_env(:storyarn, PlanStorage)

    Application.put_env(:storyarn, PlanStorage, max_json_bytes: json_bytes - 1)

    on_exit(fn ->
      restore_config(original_config)
      PlanStorage.delete(configured_key)
      PlanStorage.delete(override_key)
    end)

    assert {:error, :import_plan_too_large} =
             PlanStorage.store_at(configured_key, stored_plan)

    assert {:ok, ^override_key} =
             PlanStorage.store_at(override_key, stored_plan, max_json_bytes: json_bytes)
  end

  test "enforces the JSON limit again when loading a stored plan" do
    key = storage_key()
    stored_plan = plan(:file, %{"content" => String.duplicate("x", 256)})
    json_bytes = stored_plan |> encoded_payload() |> byte_size()

    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:ok, ^key} =
             PlanStorage.store_at(key, stored_plan, max_json_bytes: json_bytes)

    assert {:ok, %ImportPlan{source_kind: :file}} =
             PlanStorage.load(key, max_json_bytes: json_bytes)

    assert {:error, :import_plan_unavailable} =
             PlanStorage.load(key, max_json_bytes: json_bytes - 1)
  end

  test "rejects an unknown source_kind before uploading a plan" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    assert {:error, :import_plan_storage_failed} = PlanStorage.store_at(key, plan(:directory))
    assert {:error, _reason} = Storage.download(key)
  end

  test "rejects an unregistered format before uploading a plan" do
    key = storage_key()
    on_exit(fn -> PlanStorage.delete(key) end)

    unknown_format_plan = %{plan(:file) | format: :unknown_test_format}

    assert {:error, :import_plan_storage_failed} =
             PlanStorage.store_at(key, unknown_format_plan)

    assert {:error, _reason} = Storage.download(key)
  end

  defp plan(source_kind, data \\ %{}) do
    %ImportPlan{
      format: :yarn,
      parser_version: "3",
      source_kind: source_kind,
      data: data
    }
  end

  defp encoded_payload(%ImportPlan{} = plan) do
    Jason.encode!(%{
      "format" => to_string(plan.format),
      "parser_version" => plan.parser_version,
      "source_kind" => encoded_source_kind(plan.source_kind),
      "data" => plan.data,
      "issue_summary" => %{
        "warning_count" => 0,
        "error_count" => 0,
        "issue_count" => 0,
        "issues_truncated" => false,
        "counts_by_code" => %{}
      }
    })
  end

  defp encrypted_bound_payload(key, payload) do
    compressed = payload |> Jason.encode!() |> :zlib.gzip()
    nonce = :crypto.strong_rand_bytes(@binding_nonce_bytes)
    binding = :crypto.hash(:sha256, [@binding_domain, <<0>>, nonce, <<0>>, key])

    envelope =
      <<@envelope_magic::binary, @envelope_version::unsigned-8, nonce::binary, binding::binary, compressed::binary>>

    assert {:ok, encrypted} = Vault.encrypt(envelope)
    encrypted
  end

  defp stored_payload(key) do
    assert {:ok, encrypted} = Storage.download(key)
    assert {:ok, envelope} = Vault.decrypt(encrypted)

    assert <<@envelope_magic, @envelope_version::unsigned-8, _nonce::binary-size(@binding_nonce_bytes),
             _binding::binary-size(@binding_digest_bytes), compressed::binary>> = envelope

    compressed |> :zlib.gunzip() |> Jason.decode!()
  end

  defp encoded_source_kind(nil), do: "file"
  defp encoded_source_kind(source_kind), do: to_string(source_kind)

  defp restore_config(nil), do: Application.delete_env(:storyarn, PlanStorage)
  defp restore_config(config), do: Application.put_env(:storyarn, PlanStorage, config)

  defp storage_key do
    "imports/plans/#{Ecto.UUID.generate()}.plan.enc"
  end
end
