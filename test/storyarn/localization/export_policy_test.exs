defmodule Storyarn.Localization.ExportPolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Localization.ExportPolicy

  @current_hash "current-source-hash"

  test "release exports only current final translations" do
    opts = %ExportOptions{format: :unity, localization_policy: :release}

    assert ExportPolicy.text_eligible?(text(status: "final"), opts)
    refute ExportPolicy.text_eligible?(text(status: "draft"), opts)
    refute ExportPolicy.text_eligible?(text(translated_source_hash: "old-hash"), opts)
    refute ExportPolicy.text_eligible?(text(source_text_hash: nil, translated_source_hash: nil), opts)
    refute ExportPolicy.text_eligible?(text(translated_text: "  "), opts)
    refute ExportPolicy.text_eligible?(text(archived_at: DateTime.utc_now()), opts)
  end

  test "preview includes nonblank drafts and stale translations but never archived rows" do
    opts = %ExportOptions{format: :unity, localization_policy: :preview}

    assert ExportPolicy.text_eligible?(text(status: "draft"), opts)
    assert ExportPolicy.text_eligible?(text(translated_source_hash: "old-hash"), opts)
    refute ExportPolicy.text_eligible?(text(translated_text: nil), opts)
    refute ExportPolicy.text_eligible?(text(archived_at: DateTime.utc_now()), opts)
  end

  test "release voice over requires an approved eligible asset" do
    release = %ExportOptions{format: :unity, localization_policy: :release}
    preview = %ExportOptions{format: :unity, localization_policy: :preview}
    voice = text(vo_eligible: true, vo_status: "approved", vo_asset_id: 42)

    assert ExportPolicy.voiceover_eligible?(voice, release)
    assert ExportPolicy.voiceover_eligible?(%{voice | vo_status: "recorded"}, preview)
    refute ExportPolicy.voiceover_eligible?(%{voice | vo_status: "recorded"}, release)
    refute ExportPolicy.voiceover_eligible?(%{voice | vo_asset_id: nil}, preview)
    refute ExportPolicy.voiceover_eligible?(%{voice | archived_at: DateTime.utc_now()}, preview)
    refute ExportPolicy.voiceover_eligible?(%{voice | status: "draft"}, release)
    refute ExportPolicy.voiceover_eligible?(%{voice | translated_text: nil}, preview)
  end

  test "unknown policies fail with an explicit contract error" do
    assert_raise ArgumentError, ~r/unknown localization export policy/, fn ->
      ExportPolicy.text_eligible?(text(status: "final"), :unknown)
    end

    assert_raise ArgumentError, ~r/unknown localization export policy/, fn ->
      ExportPolicy.voiceover_eligible?(text(status: "final"), nil)
    end
  end

  defp text(overrides) do
    Map.merge(
      %{
        translated_text: "Hola",
        status: "final",
        source_text_hash: @current_hash,
        translated_source_hash: @current_hash,
        archived_at: nil
      },
      Map.new(overrides)
    )
  end
end
