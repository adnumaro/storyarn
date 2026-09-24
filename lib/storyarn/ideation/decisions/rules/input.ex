defmodule Storyarn.Ideation.Decisions.Rules.Input do
  @moduledoc false
  alias Storyarn.Platform.Kernel.MapAccess

  defguard valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807
  defguard valid_version(version) when is_integer(version) and version in 1..100
  def get(attrs, key), do: MapAccess.get_flexible(attrs, key)

  @verbs ~w(create change test keep discard)
  @target_types ~w(sheet flow scene)
  @states ~w(not_applied partially_applied applied no_change_needed)
  @task_schemes ~w(http https)

  def verbs, do: @verbs
  def states, do: @states

  def command(attrs) when is_map(attrs) do
    with {:ok, title} <- text(get(attrs, :title), 160),
         {:ok, conclusion} <- text(get(attrs, :conclusion), 4000),
         {:ok, reason} <- optional_text(get(attrs, :reason), 4000),
         {:ok, verb} <- verb(get(attrs, :verb)),
         {:ok, targets} <- targets(get(attrs, :targets)),
         {:ok, next_action, owner_id} <- next_action(get(attrs, :next_action), get(attrs, :next_action_owner_id)),
         responsible when valid_id(responsible) <- get(attrs, :responsible_id),
         {:ok, replaces_id} <- optional_id(get(attrs, :replaces_id)),
         {:ok, register?} <- flag(get(attrs, :register)),
         {:ok, sources} <- selections(get(attrs, :sources), true),
         {:ok, key} <- request_key(get(attrs, :request_key)) do
      {:ok,
       %{
         title: title,
         conclusion: conclusion,
         reason: reason,
         verb: verb,
         targets: targets,
         next_action: next_action,
         next_action_owner_id: owner_id,
         responsible_id: responsible,
         replaces_id: replaces_id,
         register: register?,
         sources: sources
       }, key}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_decision}
    end
  end

  def command(_), do: {:error, :invalid_decision}

  def application(attrs) when is_map(attrs) do
    with {:ok, target_key} <- optional_uuid(get(attrs, :target_key)),
         state when state in @states <- get(attrs, :state),
         {:ok, note} <- optional_text(get(attrs, :note), 1000),
         {:ok, key} <- request_key(get(attrs, :request_key)) do
      {:ok, %{target_key: target_key, state: state, note: note}, key}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_application}
    end
  end

  def application(_), do: {:error, :invalid_application}

  def task(attrs) when is_map(attrs) do
    with {:ok, url} <- task_url(get(attrs, :url)),
         {:ok, title} <- optional_text(get(attrs, :title), 160),
         {:ok, key} <- request_key(get(attrs, :request_key)) do
      {:ok, %{url: url, title: title}, key}
    else
      {:error, :invalid_request_key} = error -> error
      _ -> {:error, :invalid_task_link}
    end
  end

  def task(_), do: {:error, :invalid_task_link}

  def link_key(value) do
    case Ecto.UUID.cast(value) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_task_link}
    end
  end

  # A web address without credentials: linking a task never carries access to
  # the tracker, and Storyarn never fetches it.
  defp task_url(value) when is_binary(value) and byte_size(value) <= 2048 do
    with true <- String.valid?(value),
         url = String.trim(value),
         true <- not String.match?(url, ~r/[\s\x00-\x1f\x7f]/u),
         {:ok, %URI{scheme: scheme, host: host, userinfo: nil}} when is_binary(scheme) and is_binary(host) <-
           URI.new(url),
         true <- String.downcase(scheme) in @task_schemes and host != "" do
      {:ok, url}
    else
      _ -> {:error, :invalid_task_link}
    end
  end

  defp task_url(_), do: {:error, :invalid_task_link}

  defp verb(verb) when verb in @verbs, do: {:ok, verb}
  defp verb(_), do: {:error, :invalid_decision}

  # Existing content is named by type and ID; something that does not exist yet
  # is a label and a type, created later by a person.
  defp targets(nil), do: {:ok, []}

  defp targets(items) when is_list(items) and length(items) <= 5 do
    normalized = Enum.map(items, &target/1)

    if Enum.all?(normalized, &is_map/1) and
         length(Enum.uniq_by(normalized, &target_identity/1)) == length(normalized),
       do: {:ok, normalized},
       else: {:error, :invalid_decision_targets}
  end

  defp targets(_), do: {:error, :invalid_decision_targets}

  defp target(item) when is_map(item) do
    type = get(item, :type)
    id = get(item, :id)

    cond do
      type not in @target_types -> nil
      valid_id(id) -> %{type: type, id: id}
      is_nil(id) -> label_target(type, get(item, :label))
      true -> nil
    end
  end

  defp target(_), do: nil

  defp label_target(type, label) do
    case text(label, 160) do
      {:ok, label} -> %{type: type, label: label}
      _ -> nil
    end
  end

  defp target_identity(%{id: id, type: type}), do: {type, id}
  defp target_identity(%{label: label, type: type}), do: {type, String.downcase(label)}

  defp next_action(text, owner_id) do
    with {:ok, text} <- optional_text(text, 500),
         {:ok, owner_id} <- optional_id(owner_id),
         true <- not is_nil(text) or is_nil(owner_id) do
      {:ok, text, owner_id}
    else
      _ -> {:error, :invalid_decision}
    end
  end

  defp optional_id(nil), do: {:ok, nil}
  defp optional_id(id) when valid_id(id), do: {:ok, id}
  defp optional_id(_), do: {:error, :invalid_decision}

  defp optional_uuid(nil), do: {:ok, nil}

  defp optional_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      _ -> {:error, :invalid_application}
    end
  end

  defp flag(nil), do: {:ok, false}
  defp flag(value) when is_boolean(value), do: {:ok, value}
  defp flag(_), do: {:error, :invalid_decision}

  def request_key(value) do
    case Ecto.UUID.cast(value) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_request_key}
    end
  end

  def selections(items, expected? \\ false)

  def selections(items, expected?) when is_list(items) and length(items) in 1..20 do
    normalized = Enum.map(items, &selection(&1, expected?))

    if Enum.all?(normalized, &is_map/1) and length(Enum.uniq_by(normalized, &{&1.type, &1.id})) == length(items),
      do: {:ok, Enum.sort_by(normalized, &{&1.type, &1.id})},
      else: {:error, :invalid_decision_sources}
  end

  def selections(_, _), do: {:error, :invalid_decision_sources}

  defp selection(item, expected?) when is_map(item) do
    type = get(item, :type)
    id = get(item, :id)
    version = get(item, :version)
    identity = get(item, :identity)

    if type in ~w(idea group) and valid_id(id) and
         (not expected? or (is_integer(version) and version > 0 and match?({:ok, _}, Ecto.UUID.cast(identity)))) do
      %{type: type, id: id, version: if(expected?, do: version), identity: if(expected?, do: identity)}
    end
  end

  defp selection(_, _), do: nil

  def page(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: page_values(opts), else: {:error, :invalid_pagination}
  end

  def page(_), do: {:error, :invalid_pagination}

  defp page_values(opts) do
    limit = Keyword.get(opts, :limit, 20)
    before_id = Keyword.get(opts, :before_id)
    search = Keyword.get(opts, :search, "")
    type = Keyword.get(opts, :type, "idea")

    if is_integer(limit) and limit in 1..50 and (is_nil(before_id) or valid_id(before_id)) and
         valid_search?(search) and type in ~w(idea group) do
      {:ok, %{limit: limit, before_id: before_id, search: String.downcase(String.trim(search)), type: type}}
    else
      {:error, :invalid_pagination}
    end
  end

  defp valid_search?(search) when is_binary(search) and byte_size(search) <= 800 do
    String.valid?(search) and String.length(search) <= 200
  end

  defp valid_search?(_), do: false

  def fingerprint(operation, session_identity, decision_identity, version, attrs) do
    attrs =
      if Map.has_key?(attrs, :sources),
        do: Map.update!(attrs, :sources, &Enum.sort(Enum.map(&1, fn source -> Map.delete(source, :id) end))),
        else: attrs

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({:ideation_decision_v2, operation, session_identity, decision_identity, version, attrs})
    )
  end

  def application_fingerprint(session_identity, decision_identity, agreement, attrs) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({:ideation_decision_application_v1, session_identity, decision_identity, agreement, attrs})
    )
  end

  def task_fingerprint(session_identity, decision_identity, operation, link_key, attrs) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary(
        {:ideation_decision_task_link_v1, session_identity, decision_identity, operation, link_key, attrs}
      )
    )
  end

  defp optional_text(nil, _max), do: {:ok, nil}

  defp optional_text(value, max) when is_binary(value) do
    if String.trim(value) == "", do: {:ok, nil}, else: text(value, max)
  end

  defp optional_text(_, _), do: {:error, :invalid_decision}

  defp text(value, max) when is_binary(value) and byte_size(value) <= max * 4 do
    if String.valid?(value) and String.length(value) <= max and String.trim(value) != "",
      do: {:ok, String.trim(value)},
      else: {:error, :invalid_decision}
  end

  defp text(_, _), do: {:error, :invalid_decision}
end
