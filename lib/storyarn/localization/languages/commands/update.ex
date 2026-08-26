defmodule Storyarn.Localization.Languages.Commands.Update do
  @moduledoc false

  alias Storyarn.Localization.Languages.Commands.Locks
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.Texts
  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Repo

  def run(%ProjectLanguage{} = language, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    Repo.transaction(fn ->
      Locks.lock_project!(language.project_id)
      :ok = Texts.lock_inventory!(language.project_id)
      locked_language = Locks.lock_language!(language.project_id, language.id)

      locked_language
      |> ProjectLanguage.update_changeset(attrs)
      |> Repo.update()
      |> unwrap_language_write()
    end)
  end

  defp unwrap_language_write({:ok, language}), do: language
  defp unwrap_language_write({:error, reason}), do: Repo.rollback(reason)
end
