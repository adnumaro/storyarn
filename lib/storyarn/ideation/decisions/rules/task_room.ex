defmodule Storyarn.Ideation.Decisions.Rules.TaskRoom do
  @moduledoc false

  # A decision holds at most 20 linked tasks and 200 task-link records. Every
  # linked task keeps a record in reserve for its unlink, so no task can be left
  # linked for good.
  @max_links 20
  @max_changes 200

  def link?(changes, active), do: active < @max_links and changes + active + 2 <= @max_changes
  def edit?(changes, active), do: changes + active + 1 <= @max_changes
  def unlink?(changes, _active), do: changes < @max_changes
end
