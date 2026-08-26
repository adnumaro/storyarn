defmodule Storyarn.Projects.InterchangeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Exports.ExportOptions
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Interchange

  test "keeps export value construction and catalog behind the capability boundary" do
    assert Interchange.export_options(%{format: :yarn}) == %ExportOptions{format: :yarn}
    assert Interchange.valid_export_formats() == ExportOptions.valid_formats()
    assert is_integer(Interchange.max_sync_export_bytes())
  end

  test "keeps the import lifecycle contract behind the capability boundary" do
    assert Interchange.active_import_statuses() == ProjectImportAttempt.active_statuses()

    for {function, arity} <- [
          {:resume_storage_key, 2},
          {:subscribe_project_imports, 1},
          {:get_import_attempt, 2},
          {:update_import_strategy, 3},
          {:update_import_mode, 3},
          {:prepare_import, 4},
          {:prepare_import, 5},
          {:enqueue_import, 3},
          {:enqueue_import, 4},
          {:save_import_review, 3},
          {:resolve_import_review, 4},
          {:resume_latest_active_import, 2},
          {:resume_latest_active_import, 3},
          {:resume_import, 3},
          {:resume_import, 4},
          {:cancel_import, 2}
        ] do
      assert function_exported?(Interchange, function, arity)
    end
  end
end
