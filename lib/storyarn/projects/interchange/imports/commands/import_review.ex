defmodule Storyarn.Projects.Imports.ImportReview do
  @moduledoc false

  alias Storyarn.Projects.Imports.ImportLifecycle

  defdelegate save_import_review(scope, attempt_id, decisions), to: ImportLifecycle
  defdelegate save_import_review(scope, attempt_id, decisions, opts), to: ImportLifecycle

  defdelegate resolve_import_review(scope, attempt_id, acknowledged?, decisions),
    to: ImportLifecycle

  defdelegate resolve_import_review(scope, attempt_id, acknowledged?, decisions, opts),
    to: ImportLifecycle

  defdelegate update_import_strategy(scope, attempt_id, strategy), to: ImportLifecycle
  defdelegate update_import_mode(scope, attempt_id, mode), to: ImportLifecycle
end
