defmodule Storyarn.Localization.Providers.Commands.GlossaryState do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Access
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Repo

  @hashes_key "glossary_hashes"
  @pending_deletions_key "pending_glossary_deletions"

  @spec persist_pair(ProviderConfig.t(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, ProviderConfig.t()} | {:error, term()}
  def persist_pair(config, pair, glossary_id, hash) do
    Repo.transaction(fn ->
      config.id
      |> lock_config!()
      |> update_pair!(pair, glossary_id, hash)
    end)
  end

  @spec persist_pair_if_current(
          ProviderConfig.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, ProviderConfig.t()} | {:error, term()}
  def persist_pair_if_current(config, pair, expected_id, glossary_id, hash) do
    Repo.transaction(fn ->
      current = lock_config!(config.id)

      if Map.get(current.deepl_glossary_ids || %{}, pair) == expected_id do
        update_pair!(current, pair, glossary_id, hash)
      else
        current
      end
    end)
  end

  @spec persist_pending_deletion(ProviderConfig.t(), String.t() | nil, boolean()) ::
          {:ok, ProviderConfig.t()} | {:error, term()}
  def persist_pending_deletion(config, nil, _pending?), do: {:ok, config}

  def persist_pending_deletion(config, glossary_id, pending?) do
    Repo.transaction(fn ->
      current = lock_config!(config.id)
      settings = current.settings || %{}
      pending = Map.get(settings, @pending_deletions_key, [])

      pending =
        if pending? do
          Enum.uniq([glossary_id | pending])
        else
          List.delete(pending, glossary_id)
        end

      settings = Map.put(settings, @pending_deletions_key, pending)

      current
      |> ProviderConfig.changeset(%{settings: settings})
      |> Repo.update!()
    end)
  end

  defp lock_config!(config_id) do
    project_id =
      Repo.one(
        from(config in ProviderConfig,
          where: config.id == ^config_id,
          select: config.project_id
        )
      ) || Repo.rollback(:provider_config_not_found)

    case Access.lock_active_project(project_id, :update) do
      {:ok, _project} ->
        Repo.one!(
          from(config in ProviderConfig,
            where: config.id == ^config_id and config.project_id == ^project_id,
            lock: "FOR UPDATE"
          )
        )

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp update_pair!(config, pair, glossary_id, hash) do
    glossary_ids = put_or_delete(config.deepl_glossary_ids || %{}, pair, glossary_id)
    settings = config.settings || %{}
    hashes = settings |> Map.get(@hashes_key, %{}) |> put_or_delete(pair, hash)
    settings = Map.put(settings, @hashes_key, hashes)

    config
    |> ProviderConfig.changeset(%{deepl_glossary_ids: glossary_ids, settings: settings})
    |> Repo.update!()
  end

  defp put_or_delete(map, key, nil), do: Map.delete(map, key)
  defp put_or_delete(map, key, value), do: Map.put(map, key, value)
end
