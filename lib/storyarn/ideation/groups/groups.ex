defmodule Storyarn.Ideation.Groups do
  @moduledoc false
  alias Storyarn.Ideation.Groups.Commands
  alias Storyarn.Ideation.Groups.Queries.List

  defdelegate list_groups(scope, project_id, session_id), to: List, as: :run
  defdelegate create_group(scope, project_id, session_id, attrs), to: Commands.Create, as: :run
  defdelegate update_group(scope, project_id, session_id, id, version, attrs), to: Commands.Update, as: :run
  defdelegate move_group(scope, project_id, session_id, id, version, attrs), to: Commands.Move, as: :run
  defdelegate delete_group(scope, project_id, session_id, id, version, request_key), to: Commands.Delete, as: :run
  defdelegate restore_group(scope, project_id, session_id, id, version, attrs), to: Commands.Restore, as: :run
end
