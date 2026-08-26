defmodule Storyarn.Sheets.Versioning.Commands.MaterializationHelpersTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Repo
  alias Storyarn.Sheets.Versioning.Commands.MaterializationHelpers
  alias Storyarn.Sheets.Versioning.Data.SheetAvatarRecord
  alias Storyarn.Sheets.Versioning.Data.SheetRecord

  test "the avatar ownership join uses the versioning-owned Sheet projection" do
    assert SheetRecord.__schema__(:source) == "sheets"
    assert :project_id in SheetRecord.__schema__(:fields)
    assert :deleted_at in SheetRecord.__schema__(:fields)

    assert {:ok, nil} =
             Repo.transaction(fn ->
               MaterializationHelpers.resolve_project_external_ref(
                 9_999_991,
                 SheetAvatarRecord,
                 :sheet_avatars,
                 9_999_992,
                 []
               )
             end)
  end
end
