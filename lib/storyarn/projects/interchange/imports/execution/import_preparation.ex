defmodule Storyarn.Projects.Imports.ImportPreparation do
  @moduledoc false

  alias Storyarn.Projects.Imports.ImportLifecycle

  defdelegate parse_file(filename, binary), to: ImportLifecycle
  defdelegate preview(project_id, plan), to: ImportLifecycle
  defdelegate execute(project, plan, opts \\ []), to: ImportLifecycle
  defdelegate prepare_import(scope, project, filename, binary), to: ImportLifecycle
  defdelegate prepare_import(scope, project, filename, binary, opts), to: ImportLifecycle
  defdelegate resume_storage_key(scope, project), to: ImportLifecycle
end
