defmodule Storyarn.Projects.LocalizationOwnedPrimitivesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.LocalizationExportPolicy
  alias Storyarn.Projects.LocalizationLocaleCode
  alias Storyarn.Projects.LocalizationPlaceholderValidator
  alias Storyarn.Projects.LocalizationRuntimeKey
  alias Storyarn.Projects.LocalizationSourceContract

  test "runtime keys keep stable identifiers and escape qualified block segments" do
    assert LocalizationRuntimeKey.key("flow_node", "dialogue_1", "text") ==
             "flow_node.dialogue_1.text"

    assert LocalizationRuntimeKey.qualified_block_ref!("hero.sheet", "display name") ==
             "hero%2Esheet.display%20name"

    assert LocalizationRuntimeKey.valid_dialogue_id?("dialogue_123")
    assert LocalizationRuntimeKey.valid_response_id?("response-123")
    refute LocalizationRuntimeKey.valid_dialogue_id?("dialogue.123")
    assert_raise ArgumentError, fn -> LocalizationRuntimeKey.qualified_block_ref!("hero", nil) end
  end

  test "source contract preserves response-field and localizable-source semantics" do
    dialogue = %{
      type: "dialogue",
      deleted_at: nil,
      data: %{"responses" => [%{"id" => "response_1", "text" => "Continue"}]}
    }

    assert LocalizationSourceContract.field_metadata("flow_node", "response.response_1.text") == %{
             content_role: "response",
             vo_eligible: true
           }

    assert LocalizationSourceContract.localizable_source_field?(
             "flow_node",
             dialogue,
             "response.response_1.text"
           )

    refute LocalizationSourceContract.localizable_source_field?(
             "flow_node",
             dialogue,
             "response.missing.text"
           )

    assert LocalizationSourceContract.localizable_block?(%{
             type: "rich_text",
             is_constant: false,
             variable_name: "bio",
             deleted_at: nil
           })
  end

  test "release and preview export policies retain their distinct guarantees" do
    release_ready = %{
      translated_text: "Hola",
      status: "final",
      source_text_hash: "source-hash",
      translated_source_hash: "source-hash",
      archived_at: nil,
      vo_eligible: true,
      vo_status: "approved",
      vo_asset_id: "asset-id"
    }

    assert LocalizationExportPolicy.text_eligible?(release_ready, :release)
    assert LocalizationExportPolicy.voiceover_eligible?(release_ready, :release)

    stale = %{release_ready | translated_source_hash: "old-hash", status: "draft"}
    refute LocalizationExportPolicy.text_eligible?(stale, :release)
    assert LocalizationExportPolicy.text_eligible?(stale, :preview)
  end

  test "locale validation normalizes safe locale identifiers" do
    assert LocalizationLocaleCode.ensure_safe!("PT-BR") == "pt-br"
    assert_raise ArgumentError, fn -> LocalizationLocaleCode.ensure_safe!("../../etc/passwd") end
  end

  test "placeholder validation compares multiplicity, not just membership" do
    assert :ok =
             LocalizationPlaceholderValidator.validate_placeholders(
               "Hello {name}, {name}",
               "Hola {name}, {name}"
             )

    assert {:error, %{missing: ["{name}"], extra: ["{count}"]}} =
             LocalizationPlaceholderValidator.validate_placeholders(
               "Hello {name}, {name}",
               "Hola {name} {count}"
             )
  end
end
