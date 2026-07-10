defmodule Storyarn.Localization.GlossarySync do
  @moduledoc false

  alias Storyarn.Localization.GlossaryCrud
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.DeepL
  alias Storyarn.Repo

  @hashes_key "glossary_hashes"

  def sync(project_id, source_locale, target_locale, opts \\ []) do
    provider = Keyword.get(opts, :provider, DeepL)

    case Repo.get_by(ProviderConfig, project_id: project_id, provider: "deepl") do
      %ProviderConfig{is_active: true, api_key_encrypted: key} = config when not is_nil(key) ->
        entries = glossary_entries(project_id, source_locale, target_locale)
        pair = pair_key(source_locale, target_locale)

        if entries == [] do
          remove_remote_glossary(config, pair, provider)
        else
          replace_remote_glossary(config, pair, source_locale, target_locale, entries, provider)
        end

      _config ->
        {:error, :no_provider_configured}
    end
  end

  def synced?(project_id, source_locale, target_locale) do
    entries = glossary_entries(project_id, source_locale, target_locale)
    pair = pair_key(source_locale, target_locale)

    case Repo.get_by(ProviderConfig, project_id: project_id, provider: "deepl") do
      %ProviderConfig{} = config ->
        stored_id = Map.get(config.deepl_glossary_ids || %{}, pair)
        stored_hash = get_in(config.settings || %{}, [@hashes_key, pair])

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
    |> GlossaryCrud.list_entries(source_locale: source_locale, target_locale: target_locale)
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
      {:ok, new_id} ->
        case persist_pair(config, pair, new_id, entries_hash(entries)) do
          {:ok, updated} ->
            maybe_delete(provider, old_id, config)
            {:ok, updated}

          {:error, _reason} = error ->
            maybe_delete(provider, new_id, config)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp remove_remote_glossary(config, pair, provider) do
    old_id = Map.get(config.deepl_glossary_ids || %{}, pair)

    with {:ok, updated} <- persist_pair(config, pair, nil, nil) do
      maybe_delete(provider, old_id, config)
      {:ok, updated}
    end
  end

  defp persist_pair(config, pair, glossary_id, hash) do
    glossary_ids = put_or_delete(config.deepl_glossary_ids || %{}, pair, glossary_id)
    settings = config.settings || %{}
    hashes = settings |> Map.get(@hashes_key, %{}) |> put_or_delete(pair, hash)
    settings = Map.put(settings, @hashes_key, hashes)

    config
    |> ProviderConfig.changeset(%{deepl_glossary_ids: glossary_ids, settings: settings})
    |> Repo.update()
  end

  defp put_or_delete(map, key, nil), do: Map.delete(map, key)
  defp put_or_delete(map, key, value), do: Map.put(map, key, value)

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
