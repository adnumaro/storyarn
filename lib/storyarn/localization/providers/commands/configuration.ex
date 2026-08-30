defmodule Storyarn.Localization.Providers.Commands.Configuration do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.ProjectAccess
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Repo

  @spec upsert(map(), %{required(:id) => pos_integer()}, map()) ::
          {:ok, ProviderConfig.t()} | {:error, Ecto.Changeset.t() | term()}
  def upsert(%{user: %{id: actor_id}} = actor_scope, %{id: project_id}, attrs)
      when is_integer(actor_id) and actor_id > 0 and is_integer(project_id) and project_id > 0 and is_map(attrs) do
    Repo.transaction(fn -> upsert_transaction(actor_scope, project_id, attrs) end)
  end

  def upsert(_actor_scope, _project, _attrs), do: {:error, :unauthorized}

  defp upsert_transaction(actor_scope, project_id, attrs) do
    case ProjectAccess.lock_active_project(project_id, :update) do
      {:ok, locked_project} ->
        case ProjectAccess.authorize_locked_owner(actor_scope, locked_project) do
          :ok ->
            locked_project.id
            |> get_locked_config()
            |> config_changeset(locked_project.id, attrs)
            |> persist_config()

          {:error, reason} ->
            Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp get_locked_config(project_id) do
    Repo.one(
      from(config in ProviderConfig,
        where:
          config.project_id == ^project_id and
            config.provider == "deepl",
        lock: "FOR UPDATE"
      )
    )
  end

  defp config_changeset(nil, project_id, attrs) do
    ProviderConfig.changeset(
      %ProviderConfig{project_id: project_id},
      Map.put(attrs, "provider", "deepl")
    )
  end

  defp config_changeset(%ProviderConfig{} = config, _project_id, attrs) do
    ProviderConfig.changeset(config, attrs)
  end

  defp persist_config(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, config} -> config
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
