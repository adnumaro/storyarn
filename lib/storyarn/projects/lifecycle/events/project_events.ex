defmodule Storyarn.Projects.Events do
  @moduledoc """
  Project-owned business event vocabulary.

  The Project coordination boundary owns the facts and payloads. Platform owns
  cross-cutting reactions such as product metrics.
  """

  alias Storyarn.Platform

  @event_types [
    :asset_uploaded,
    :project_created,
    :template_installation_completed,
    :template_installation_failed,
    :template_installation_requested,
    :version_control_settings_updated
  ]

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    Platform.react_to_event(scope_or_user, :projects, event_type, payload)
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @doc "Publishes the product fact for a created project."
  @spec project_created(term(), map()) :: :ok
  def project_created(scope_or_user, %{id: _} = project) do
    emit(scope_or_user, :project_created, %{
      project_id: project.id,
      workspace_id: project.workspace_id,
      project_type: project.project_type,
      project_subtype: project.project_subtype
    })
  end

  def project_created(_scope_or_user, _project), do: :ok

  @doc "Publishes the product fact for a requested template installation."
  @spec template_installation_requested(term(), map(), map()) :: :ok
  def template_installation_requested(scope, %{id: _} = install, %{id: _} = template) do
    emit(scope, :template_installation_requested, %{
      installation_id: install.id,
      template_id: template.id,
      template_version_id: install.project_template_version_id,
      workspace_id: install.workspace_id,
      source: install.source,
      visibility: template.visibility
    })
  end

  def template_installation_requested(_scope, _install, _template), do: :ok

  @doc "Publishes the product fact for a finished template installation."
  @spec template_installation_finished(term(), String.t(), map()) :: :ok
  def template_installation_finished(scope_or_user, status, payload) when is_map(payload) do
    event = if status == "completed", do: :template_installation_completed, else: :template_installation_failed
    emit(scope_or_user, event, payload)
  end

  @doc "Publishes the product fact for updated version control settings."
  @spec version_control_settings_updated(term(), map(), map()) :: :ok
  def version_control_settings_updated(scope, %{id: _} = project, attrs) when is_map(attrs) do
    emit(scope, :version_control_settings_updated, %{
      auto_version_flows: attrs.auto_version_flows,
      auto_version_scenes: attrs.auto_version_scenes,
      auto_version_sheets: attrs.auto_version_sheets,
      project_id: project.id
    })
  end

  def version_control_settings_updated(_scope, _project, _attrs), do: :ok

  @doc "Publishes the product fact for an uploaded asset, attributing system uploads."
  @spec asset_uploaded(term(), map()) :: :ok
  def asset_uploaded(%{id: _} = user, payload) when is_map(payload), do: emit(user, :asset_uploaded, payload)
  def asset_uploaded(_user, payload) when is_map(payload), do: emit(:system, :asset_uploaded, payload)
end
