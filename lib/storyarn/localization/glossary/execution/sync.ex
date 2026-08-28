defmodule Storyarn.Localization.Glossary.Execution.Sync do
  @moduledoc false

  alias Storyarn.Localization.Glossary
  alias Storyarn.Localization.Providers

  @hashes_key "glossary_hashes"
  @pending_deletions_key "pending_glossary_deletions"

  def sync(project_id, source_locale, target_locale, opts \\ []) do
    provider = Keyword.get(opts, :provider, Providers.default_adapter())

    case Providers.get_config(project_id) do
      %{is_active: true, api_key_encrypted: key} = config when not is_nil(key) ->
        sync_config(config, project_id, source_locale, target_locale, provider)

      _config ->
        {:error, :no_provider_configured}
    end
  end

  def synced?(project_id, source_locale, target_locale) do
    entries = glossary_entries(project_id, source_locale, target_locale)
    pair = pair_key(source_locale, target_locale)

    case Providers.get_config(project_id) do
      %{deepl_glossary_ids: glossary_ids, settings: settings} ->
        stored_id = Map.get(glossary_ids || %{}, pair)
        stored_hash = get_in(settings || %{}, [@hashes_key, pair])
        pending_deletions = Map.get(settings || %{}, @pending_deletions_key, [])

        pending_deletions == [] and
          if entries == [] do
            is_nil(stored_id)
          else
            is_binary(stored_id) and stored_hash == entries_hash(entries)
          end

      nil ->
        false
    end
  end

  def pair_key(source_locale, target_locale) do
    "#{String.upcase(source_locale)}-#{String.upcase(target_locale)}"
  end

  defp glossary_entries(project_id, source_locale, target_locale) do
    project_id
    |> Glossary.list_entries(source_locale: source_locale, target_locale: target_locale)
    |> Enum.map(fn entry ->
      target =
        if entry.do_not_translate or blank?(entry.target_term) do
          entry.source_term
        else
          entry.target_term
        end

      {entry.source_term, target}
    end)
  end

  defp replace_remote_glossary(config, pair, source_locale, target_locale, entries, provider) do
    old_id = Map.get(config.deepl_glossary_ids || %{}, pair)
    name = "Storyarn #{config.project_id} #{pair}"

    case provider.create_glossary(name, source_locale, target_locale, entries, config) do
      {:ok, new_id} -> persist_replacement(config, pair, old_id, new_id, entries, provider)
      {:error, _reason} = error -> error
    end
  end

  defp sync_config(config, project_id, source_locale, target_locale, provider) do
    with {:ok, config} <- retry_pending_deletions(config, provider) do
      entries = glossary_entries(project_id, source_locale, target_locale)
      pair = pair_key(source_locale, target_locale)
      sync_entries(config, pair, source_locale, target_locale, entries, provider)
    end
  end

  defp sync_entries(config, pair, _source_locale, _target_locale, [], provider) do
    remove_remote_glossary(config, pair, provider)
  end

  defp sync_entries(config, pair, source_locale, target_locale, entries, provider) do
    replace_remote_glossary(config, pair, source_locale, target_locale, entries, provider)
  end

  defp persist_replacement(config, pair, old_id, new_id, entries, provider) do
    case Providers.persist_glossary_pair(config, pair, new_id, entries_hash(entries)) do
      {:ok, updated} ->
        finish_replacement(updated, old_id, provider)

      {:error, _reason} = error ->
        maybe_delete(provider, new_id, config)
        error
    end
  end

  defp finish_replacement(updated, old_id, provider) do
    case maybe_delete(provider, old_id, updated) do
      :ok -> {:ok, updated}
      {:error, _reason} = error -> track_failed_cleanup(updated, old_id, error)
    end
  end

  defp track_failed_cleanup(updated, old_id, error) do
    case Providers.persist_pending_glossary_deletion(updated, old_id, true) do
      {:ok, _config} -> error
      {:error, persist_reason} -> {:error, {:cleanup_tracking_failed, persist_reason}}
    end
  end

  defp remove_remote_glossary(config, pair, provider) do
    old_id = Map.get(config.deepl_glossary_ids || %{}, pair)

    with :ok <- maybe_delete(provider, old_id, config) do
      Providers.persist_glossary_pair_if_current(config, pair, old_id, nil, nil)
    end
  end

  defp retry_pending_deletions(config, provider) do
    config.settings
    |> Kernel.||(%{})
    |> Map.get(@pending_deletions_key, [])
    |> Enum.reduce_while({:ok, config}, fn glossary_id, {:ok, current} ->
      retry_pending_deletion(current, glossary_id, provider)
    end)
  end

  defp retry_pending_deletion(config, glossary_id, provider) do
    with :ok <- maybe_delete(provider, glossary_id, config),
         {:ok, updated} <- Providers.persist_pending_glossary_deletion(config, glossary_id, false) do
      {:cont, {:ok, updated}}
    else
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp maybe_delete(_provider, nil, _config), do: :ok
  defp maybe_delete(provider, glossary_id, config), do: provider.delete_glossary(glossary_id, config)

  defp entries_hash(entries) do
    entries
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(value) == ""
end
