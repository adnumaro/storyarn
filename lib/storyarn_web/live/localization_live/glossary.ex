defmodule StoryarnWeb.LocalizationLive.Glossary do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Localization
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      active_tool={:localization}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.LocalizationSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "selected_locale" => @selected_locale,
          "can_edit" => @can_edit,
          "active_tool" => "localization",
          "dashboard_url" =>
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.vue
        v-component="live/localization/glossary/LocalizationGlossary"
        v-socket={@socket}
        v-inject="project-layout"
        id="localization-glossary"
        class="contents"
        source-language={serialize_language(@source_language)}
        target-languages={Enum.map(@target_languages, &serialize_language/1)}
        selected-locale={@selected_locale}
        entries={Enum.map(@entries, &serialize_entry/1)}
        can-edit={@can_edit}
        has-provider={@has_provider}
        synced={@synced}
        back-url={texts_url(assigns)}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    {:ok, source_language} = Localization.ensure_source_language(project)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id)
      )
    end

    {:ok,
     socket
     |> assign(:source_language, source_language)
     |> assign(:target_languages, Localization.get_target_languages(project.id))
     |> assign(:selected_locale, nil)
     |> assign(:entries, [])
     |> assign(:synced, false)
     |> assign(:has_provider, Localization.has_active_provider?(project.id))
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))}
  end

  @impl true
  def handle_params(%{"locale" => locale}, _url, socket) do
    locale =
      if Enum.any?(socket.assigns.target_languages, &(&1.locale_code == locale)) do
        locale
      end

    {:noreply, socket |> assign(:selected_locale, locale) |> load_entries()}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    if Enum.any?(socket.assigns.target_languages, &(&1.locale_code == locale)) do
      {:noreply,
       push_patch(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/localization/glossary/#{locale}"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_entry", params, socket) do
    with_edit_permission(socket, fn -> save_entry(socket, params) end)
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    with_edit_permission(socket, fn ->
      with {:ok, id} <- parse_id(id),
           entry when not is_nil(entry) <- Localization.get_glossary_entry(socket.assigns.project.id, id),
           {:ok, _entry} <- Localization.delete_glossary_entry(entry) do
        {:reply, %{ok: true}, load_entries(socket)}
      else
        _reason -> {:reply, %{ok: false, error: "entry_not_found"}, socket}
      end
    end)
  end

  def handle_event("sync_glossary", _params, socket) do
    with_edit_permission(socket, fn ->
      case Localization.sync_deepl_glossary(
             socket.assigns.project.id,
             socket.assigns.source_language.locale_code,
             socket.assigns.selected_locale
           ) do
        {:ok, _config} -> {:reply, %{ok: true}, load_entries(socket)}
        {:error, reason} -> {:reply, %{ok: false, error: inspect(reason)}, socket}
      end
    end)
  end

  @impl true
  def handle_info({:languages_changed, _payload}, socket) do
    target_languages = Localization.get_target_languages(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:target_languages, target_languages)
     |> assign(:has_provider, Localization.has_active_provider?(socket.assigns.project.id))
     |> load_entries()}
  end

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp save_entry(socket, params) do
    attrs = %{
      "source_term" => params["source_term"],
      "source_locale" => socket.assigns.source_language.locale_code,
      "target_term" => params["target_term"],
      "target_locale" => socket.assigns.selected_locale,
      "context" => params["context"],
      "do_not_translate" => params["do_not_translate"] in [true, "true"]
    }

    result =
      case parse_optional_id(params["id"]) do
        {:ok, nil} ->
          Localization.create_glossary_entry(socket.assigns.project, attrs)

        {:ok, id} ->
          case Localization.get_glossary_entry(socket.assigns.project.id, id) do
            nil -> {:error, :not_found}
            entry -> Localization.update_glossary_entry(entry, attrs)
          end

        :error ->
          {:error, :invalid_id}
      end

    case result do
      {:ok, entry} -> {:reply, %{ok: true, entry: serialize_entry(entry)}, load_entries(socket)}
      {:error, %Ecto.Changeset{} = changeset} -> {:reply, %{ok: false, errors: changeset_errors(changeset)}, socket}
      {:error, reason} -> {:reply, %{ok: false, error: inspect(reason)}, socket}
    end
  end

  defp load_entries(%{assigns: %{selected_locale: nil}} = socket) do
    assign(socket, entries: [], synced: false)
  end

  defp load_entries(socket) do
    project_id = socket.assigns.project.id
    source_locale = socket.assigns.source_language.locale_code
    target_locale = socket.assigns.selected_locale

    socket
    |> assign(
      :entries,
      Localization.list_glossary_entries(project_id,
        source_locale: source_locale,
        target_locale: target_locale
      )
    )
    |> assign(:synced, Localization.glossary_synced?(project_id, source_locale, target_locale))
  end

  defp with_edit_permission(socket, fun) do
    case Authorize.authorize(socket, :edit_content) do
      :ok -> fun.()
      {:error, :unauthorized} -> {:reply, %{ok: false, error: "unauthorized"}, socket}
    end
  end

  defp serialize_language(language), do: %{localeCode: language.locale_code, name: language.name}

  defp serialize_entry(entry) do
    %{
      id: entry.id,
      sourceTerm: entry.source_term,
      targetTerm: entry.target_term || "",
      context: entry.context || "",
      doNotTranslate: entry.do_not_translate
    }
  end

  defp texts_url(%{selected_locale: nil}), do: nil

  defp texts_url(assigns) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/localization/texts/#{assigns.selected_locale}"
  end

  defp changeset_errors(changeset) do
    Map.new(changeset.errors, fn {field, {message, _metadata}} -> {field, message} end)
  end

  defp parse_optional_id(nil), do: {:ok, nil}
  defp parse_optional_id(""), do: {:ok, nil}
  defp parse_optional_id(value), do: parse_id(value)

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _other -> :error
    end
  end

  defp parse_id(_value), do: :error
end
