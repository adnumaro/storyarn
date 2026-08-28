defmodule Storyarn.Localization.Glossary.Commands.Entries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.ProjectAccess
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  def create(%{id: project_id}, attrs) when is_integer(project_id) and project_id > 0 do
    attrs = MapAccess.stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, locked_project} <- ProjectAccess.lock_active_project(project_id, :update),
           {:ok, entry} <-
             %GlossaryEntry{project_id: locked_project.id}
             |> GlossaryEntry.create_changeset(attrs)
             |> Repo.insert() do
        entry
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update(%GlossaryEntry{} = entry, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, locked_entry} <- lock_active_entry(entry.id, entry.project_id),
           {:ok, updated_entry} <-
             locked_entry
             |> GlossaryEntry.update_changeset(attrs)
             |> Repo.update() do
        updated_entry
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete(%GlossaryEntry{} = entry) do
    Repo.transaction(fn ->
      with {:ok, locked_entry} <- lock_active_entry(entry.id, entry.project_id),
           {:ok, deleted_entry} <- Repo.delete(locked_entry) do
        deleted_entry
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def bulk_import(attrs_list) do
    attrs_list
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(GlossaryEntry, chunk) end)
  end

  defp lock_active_entry(entry_id, project_id) when is_integer(entry_id) and is_integer(project_id) do
    with {:ok, _project} <- ProjectAccess.lock_active_project(project_id, :update),
         %GlossaryEntry{} = entry <-
           Repo.one(
             from(entry in GlossaryEntry,
               where: entry.id == ^entry_id and entry.project_id == ^project_id,
               lock: "FOR UPDATE"
             )
           ) do
      {:ok, entry}
    else
      nil -> {:error, :glossary_entry_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_active_entry(_entry_id, _project_id), do: {:error, :glossary_entry_not_found}
end
