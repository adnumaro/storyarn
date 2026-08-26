defmodule Storyarn.Sheets.Localization.Commands.ProjectionTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Localization.Data.LocalizedTextRecord

  setup do
    project = project_fixture()
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    %{project: project}
  end

  test "Sheet writers preserve the localization lifecycle without calling Localization", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "Main Character"})

    assert %{source_text: "Main Character", content_role: "speaker_name"} =
             active_text!("sheet", sheet.id)

    block =
      block_fixture(sheet, %{
        type: "rich_text",
        variable_name: "biography",
        value: %{"content" => "<p>Original biography</p>"}
      })

    original = active_text!("block", block.id)
    assert original.source_field == "value.content"
    assert original.word_count == 2
    assert original.content_role == "runtime_value"

    Repo.update_all(
      from(text in LocalizedTextRecord, where: text.id == ^original.id),
      set: [
        translated_text: "Biografía original",
        translated_source_hash: original.source_text_hash,
        status: "final"
      ]
    )

    assert {:ok, updated_block} =
             Sheets.update_block_value(block, %{"content" => "<p>Rewritten biography</p>"})

    updated = active_text!("block", block.id)
    assert updated.id == original.id
    assert updated.source_text == "<p>Rewritten biography</p>"
    assert updated.translated_text == "Biografía original"
    assert updated.status == "review"

    assert {:ok, constant_block} = Sheets.update_block(updated_block, %{is_constant: true})
    assert %{archive_reason: "source_not_runtime"} = archived_text!("block", block.id)

    assert {:ok, runtime_block} = Sheets.update_block(constant_block, %{is_constant: false})
    assert %{id: id, archived_at: nil} = active_text!("block", block.id)
    assert id == original.id

    assert {:ok, deleted_block} = Sheets.delete_block(runtime_block)
    assert %{archive_reason: "source_deleted"} = archived_text!("block", block.id)

    assert {:ok, _restored_block} = Sheets.restore_block(deleted_block)
    assert %{id: ^id, archived_at: nil} = active_text!("block", block.id)

    assert {:ok, renamed_sheet} = Sheets.update_sheet(sheet, %{name: "Renamed Character"})
    assert %{source_text: "Renamed Character"} = active_text!("sheet", sheet.id)

    assert {:ok, trashed_sheet} = Sheets.delete_sheet(renamed_sheet)
    assert %{archive_reason: "source_deleted"} = archived_text!("sheet", sheet.id)
    assert %{archive_reason: "source_deleted"} = archived_text!("block", block.id)

    assert {:ok, restored_sheet} = Sheets.restore_sheet(trashed_sheet)
    assert %{archived_at: nil} = active_text!("sheet", sheet.id)
    assert %{archived_at: nil} = active_text!("block", block.id)

    assert {:ok, _deleted_sheet} = Sheets.permanently_delete_sheet(restored_sheet)
    refute text_exists?("sheet", sheet.id)
    refute text_exists?("block", block.id)
  end

  test "concurrent Sheet writes leave one projection matching the committed block", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "Concurrent"})

    block =
      block_fixture(sheet, %{
        type: "text",
        variable_name: "line",
        value: %{"content" => "Before"}
      })

    results =
      ["First committed value", "Second committed value"]
      |> Task.async_stream(
        &Sheets.update_block_value(block, %{"content" => &1}),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %Block{}}, &1))

    committed_block = Repo.get!(Block, block.id)
    texts = all_texts("block", block.id)

    assert [%LocalizedTextRecord{} = text] = texts
    assert text.source_text == committed_block.value["content"]
    assert text.source_text_hash == hash(text.source_text)
    assert is_nil(text.archived_at)
  end

  defp active_text!(source_type, source_id) do
    Repo.one!(
      from(text in LocalizedTextRecord,
        where:
          text.source_type == ^source_type and text.source_id == ^source_id and
            is_nil(text.archived_at)
      )
    )
  end

  defp archived_text!(source_type, source_id) do
    Repo.one!(
      from(text in LocalizedTextRecord,
        where:
          text.source_type == ^source_type and text.source_id == ^source_id and
            not is_nil(text.archived_at)
      )
    )
  end

  defp all_texts(source_type, source_id) do
    Repo.all(
      from(text in LocalizedTextRecord,
        where: text.source_type == ^source_type and text.source_id == ^source_id
      )
    )
  end

  defp text_exists?(source_type, source_id) do
    Repo.exists?(
      from(text in LocalizedTextRecord,
        where: text.source_type == ^source_type and text.source_id == ^source_id
      )
    )
  end

  defp hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
end
