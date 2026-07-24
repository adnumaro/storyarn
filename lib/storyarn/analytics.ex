defmodule Storyarn.Analytics do
  @moduledoc """
  Privacy-safe product analytics facade.

  Keep event names and properties coarse. Story content, filenames, URLs, slugs,
  descriptions, emails, and imported/exported payloads must not be sent here.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Analytics.NoopAdapter
  alias Storyarn.Analytics.PostHogAdapter

  require Logger

  @event_property_keys %{
    "asset uploaded" => MapSet.new(~w(asset_type content_type created_variant project_id purpose size_bucket)),
    "flow analysis run" =>
      MapSet.new(~w(source stale finding_count dismissed_count error_count warning_count duration_bucket)),
    "flow analysis finding dismissed" => MapSet.new(~w(rule_id rule_version category severity reason_code)),
    "flow analysis finding restored" => MapSet.new(~w(rule_id rule_version reason_code)),
    "flow analysis evidence navigated" => MapSet.new(~w(evidence_type)),
    "flow debug started" => MapSet.new(~w(flow_id project_id)),
    "flow node created" => MapSet.new(~w(creation_method flow_id has_parent node_type project_id)),
    "flow player started" => MapSet.new(~w(flow_id project_id)),
    "onboarding tutorial interacted" => MapSet.new(~w(action guide source)),
    "page viewed" => MapSet.new(~w(route_family)),
    "palette command executed" => MapSet.new(~w(command_id surface)),
    "palette opened" => MapSet.new(~w(surface)),
    "palette search no results" => MapSet.new(~w(query_length surface)),
    "project created" => MapSet.new(~w(project_id project_subtype project_type project_type_other workspace_id)),
    "project template installation requested" =>
      MapSet.new(~w(installation_id source template_id template_version_id visibility workspace_id)),
    "project template installation completed" =>
      MapSet.new(~w(duration_bucket error_code installation_id project_id source template_version_id workspace_id)),
    "project template installation failed" =>
      MapSet.new(~w(duration_bucket error_code installation_id project_id source template_version_id workspace_id)),
    "scene exploration started" => MapSet.new(~w(has_saved_session project_id scene_id)),
    "sequence track updated" =>
      MapSet.new(~w(changed_asset changed_volume flow_id has_asset project_id sequence_id track_kind)),
    "sequence visual layer created" => MapSet.new(~w(flow_id has_asset layer_kind project_id sequence_id slot)),
    "sequence visual layer updated" =>
      MapSet.new(~w(changed_asset flow_id has_asset layer_kind project_id sequence_id slot)),
    "sheet block created" => MapSet.new(~w(block_type creation_method project_id scope sheet_id)),
    "user logged in" => MapSet.new(~w(auth_method)),
    "user signed up" => MapSet.new(~w(auth_method)),
    "version compared" => MapSet.new(~w(entity_type project_id)),
    "version control settings updated" =>
      MapSet.new(~w(auto_snapshots_enabled auto_version_flows auto_version_scenes auto_version_sheets project_id)),
    "version created" => MapSet.new(~w(entity_type project_id)),
    "version panel opened" => MapSet.new(~w(entity_type project_id)),
    "version restored" => MapSet.new(~w(entity_type project_id skip_pre_snapshot)),
    "workspace created" => MapSet.new(~w(workspace_id))
  }

  @allowed_person_property_keys MapSet.new(~w(
    created_at
    is_super_admin
    locale
  ))

  @type properties :: %{optional(atom() | String.t()) => term()}

  @doc """
  Captures an event for the current user.
  """
  @spec track(Scope.t() | User.t() | nil, String.t(), properties()) :: :ok
  def track(scope_or_user, event_name, properties \\ %{})

  def track(%Scope{user: user}, event_name, properties), do: track(user, event_name, properties)

  def track(%User{} = user, event_name, properties) when is_binary(event_name) do
    capture(%{
      event: event_name,
      distinct_id: distinct_id(user),
      properties: sanitize_properties(event_name, properties)
    })
  end

  def track(_scope_or_user, _event_name, _properties), do: :ok

  @doc """
  Captures an event that is not attributable to a logged-in user.
  """
  @spec track_system(String.t(), properties()) :: :ok
  def track_system(event_name, properties \\ %{})

  def track_system(event_name, properties) when is_binary(event_name) do
    capture(%{
      event: event_name,
      distinct_id: "system",
      properties: sanitize_properties(event_name, properties)
    })
  end

  def track_system(_event_name, _properties), do: :ok

  @doc """
  Identifies the current user without exposing email or display name.
  """
  @spec identify_user(User.t() | nil, properties()) :: :ok
  def identify_user(user, properties \\ %{})

  def identify_user(%User{} = user, properties) do
    identify(%{
      distinct_id: distinct_id(user),
      properties:
        user
        |> default_person_properties()
        |> Map.merge(sanitize_person_properties(properties))
    })
  end

  def identify_user(_user, _properties), do: :ok

  @doc """
  Returns frontend-safe PostHog config for root metadata.
  """
  @spec frontend_config(Scope.t() | User.t() | nil) :: map() | nil
  def frontend_config(scope_or_user)

  def frontend_config(%Scope{user: user}), do: frontend_config(user)

  def frontend_config(%User{} = user) do
    case frontend_base_config() do
      {:ok, config} ->
        Map.merge(config, %{
          distinct_id: distinct_id(user),
          error_tracking_enabled: error_tracking_enabled?(),
          user_locale: user.locale,
          user_super_admin: user.is_super_admin
        })

      _ ->
        nil
    end
  end

  def frontend_config(nil) do
    case frontend_base_config() do
      {:ok, config} ->
        Map.merge(config, %{
          distinct_id: nil,
          error_tracking_enabled: error_tracking_enabled?(),
          user_locale: nil,
          user_super_admin: nil
        })

      _ ->
        nil
    end
  end

  def frontend_config(_scope_or_user), do: nil

  @doc """
  Applies the event-specific property allowlist.
  """
  @spec sanitize_properties(String.t(), properties()) :: %{String.t() => term()}
  def sanitize_properties(event_name, properties) when is_binary(event_name) and is_map(properties) do
    filter_properties(properties, Map.get(@event_property_keys, event_name, MapSet.new()))
  end

  def sanitize_properties(_event_name, _properties), do: %{}

  defp sanitize_person_properties(properties) when is_map(properties) do
    filter_properties(properties, @allowed_person_property_keys)
  end

  defp sanitize_person_properties(_properties), do: %{}

  defp filter_properties(properties, allowed_keys) do
    Enum.reduce(properties, %{}, fn {key, value}, acc ->
      key = normalize_key(key)

      if MapSet.member?(allowed_keys, key) and allowed_value?(value) do
        Map.put(acc, key, normalize_value(value))
      else
        acc
      end
    end)
  end

  defp capture(%{event: event_name} = payload) do
    if allowed_event?(event_name) do
      dispatch(:capture, payload)
    else
      :ok
    end
  end

  defp identify(payload), do: dispatch(:identify, payload)

  defp dispatch(function, payload) do
    adapter = adapter()

    if adapter == NoopAdapter do
      :ok
    else
      dispatch_with_adapter(adapter, function, payload)
    end
  end

  defp dispatch_with_adapter(PostHogAdapter, function, payload) do
    case Process.whereis(Storyarn.TaskSupervisor) do
      nil ->
        safe_apply(PostHogAdapter, function, payload)

      _pid ->
        Task.Supervisor.start_child(Storyarn.TaskSupervisor, fn ->
          safe_apply(PostHogAdapter, function, payload)
        end)

        :ok
    end
  end

  defp dispatch_with_adapter(adapter, function, payload) do
    safe_apply(adapter, function, payload)
  end

  defp safe_apply(adapter, function, payload) do
    apply(adapter, function, [payload])
    :ok
  rescue
    error ->
      Logger.debug("Analytics dispatch failed: #{Exception.message(error)}")
      :ok
  catch
    kind, reason ->
      Logger.debug("Analytics dispatch failed: #{inspect({kind, reason})}")
      :ok
  end

  defp adapter do
    Application.get_env(:storyarn, :analytics_adapter) ||
      if enabled?(), do: PostHogAdapter, else: NoopAdapter
  end

  defp frontend_base_config do
    sdk_config = sdk_config()
    frontend_config = frontend_config_env()
    api_key = Keyword.get(sdk_config, :api_key)
    host = Keyword.get(sdk_config, :api_host, "https://eu.i.posthog.com")

    if Keyword.get(frontend_config, :frontend_enabled, false) and present?(api_key) and present?(host) do
      {:ok, %{api_key: api_key, host: String.trim_trailing(host, "/")}}
    else
      :error
    end
  end

  defp enabled? do
    config = sdk_config()
    Keyword.get(config, :enable, false) and present?(Keyword.get(config, :api_key))
  end

  defp error_tracking_enabled? do
    config = frontend_config_env()
    Keyword.get(config, :error_tracking_enabled, false) and enabled?()
  end

  defp sdk_config, do: Application.get_all_env(:posthog)

  defp frontend_config_env, do: Application.get_env(:storyarn, :posthog_frontend, [])

  defp present?(value), do: is_binary(value) and value != ""

  defp distinct_id(%User{id: id}), do: "user:#{id}"

  defp allowed_event?(event_name), do: Map.has_key?(@event_property_keys, event_name)

  defp default_person_properties(user) do
    %{
      "created_at" => normalize_value(user.inserted_at),
      "is_super_admin" => user.is_super_admin,
      "locale" => user.locale
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_key), do: nil

  defp allowed_value?(value)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value) or is_nil(value), do: true

  defp allowed_value?(%DateTime{}), do: true
  defp allowed_value?(%NaiveDateTime{}), do: true
  defp allowed_value?(%Date{}), do: true
  defp allowed_value?(_value), do: false

  defp normalize_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp normalize_value(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp normalize_value(%Date{} = date), do: Date.to_iso8601(date)
  defp normalize_value(value), do: value
end
