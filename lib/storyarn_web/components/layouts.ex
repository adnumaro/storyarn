defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS
  alias Storyarn.Analytics
  alias Storyarn.FeatureFlags
  alias Storyarn.Publication.Locales, as: PublicLocales

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Mounts the global command palette island (Meta+K / Ctrl+K).

  Rendered by authenticated application layouts — workspace, project and
  settings surfaces — never on auth/public/docs pages.
  """
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue events)"
  attr :current_scope, :map, required: true, doc: "actor used to resolve command feature flags"

  def command_palette(assigns) do
    ~H"""
    <div id="command-palette">
      <.vue
        v-component="live/layouts/CommandPalette"
        v-socket={@socket}
        id="command-palette-island"
        feature-flags={command_palette_feature_flags(@current_scope)}
      />
    </div>
    """
  end

  defp command_palette_feature_flags(%{user: user}) when not is_nil(user) do
    %{aiIntegrations: FeatureFlags.enabled?(:ai_integrations, for: user)}
  end

  defp command_palette_feature_flags(_scope), do: %{aiIntegrations: false}

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} socket={@socket} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue events)"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"
  attr :privacy_url, :string, default: "/privacy#cookies"
  attr :terms_url, :string, default: "/terms"

  def flash_group(assigns) do
    assigns =
      assigns
      |> assign(:flash_messages, flash_messages(assigns.flash))
      |> assign(:network_flash, network_flash_messages())

    ~H"""
    <div
      id={@id}
      aria-live="polite"
      phx-disconnected={
        JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        |> show(".phx-client-error #client-error")
        |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        |> show(".phx-server-error #server-error")
      }
      phx-connected={
        hide("#client-error")
        |> JS.set_attribute({"hidden", ""}, to: "#client-error")
        |> hide("#server-error")
        |> JS.set_attribute({"hidden", ""}, to: "#server-error")
      }
    >
      <.vue
        v-component="live/layouts/flash/FlashGroup"
        v-socket={@socket}
        id={"#{@id}-content"}
        flash={@flash_messages}
        network={@network_flash}
      />
      <.vue
        v-component="live/public/CookieConsent"
        v-socket={@socket}
        id={"#{@id}-cookie-consent"}
        privacy-url={@privacy_url}
        terms-url={@terms_url}
      />
    </div>
    """
  end

  defp flash_messages(flash) do
    %{
      info: Phoenix.Flash.get(flash, :info),
      warning: Phoenix.Flash.get(flash, :warning),
      error: Phoenix.Flash.get(flash, :error)
    }
  end

  defp network_flash_messages do
    %{
      clientTitle: gettext("We can't find the internet"),
      serverTitle: gettext("Something went wrong!"),
      reconnecting: gettext("Attempting to reconnect")
    }
  end

  def posthog_frontend_config(assigns) do
    assigns
    |> current_scope_from_assigns()
    |> Analytics.frontend_config()
  end

  def seo_title(assigns) do
    page_title = assigns[:page_title]

    if is_binary(page_title) && String.trim(page_title) != "" do
      String.trim(page_title)
    else
      "Storyarn"
    end
  end

  def seo_description(assigns) do
    description = assigns[:seo_description]

    if is_binary(description) && String.trim(description) != "" do
      String.trim(description)
    else
      "Storyarn is a narrative design platform for video games, branching dialogue, worldbuilding, scenes, localization, debugging, and engine-ready export."
    end
  end

  def seo_type(assigns) do
    case assigns[:seo_type] do
      type when is_binary(type) and type != "" -> type
      _ -> "website"
    end
  end

  def seo_canonical_url(assigns) do
    case assigns[:canonical_url] do
      url when is_binary(url) and url != "" -> absolute_url(url)
      _ -> assigns |> current_request_path() |> absolute_url()
    end
  end

  def seo_image_url(assigns) do
    case assigns[:seo_image_url] do
      url when is_binary(url) and url != "" -> url
      _ -> absolute_url("/images/landing/storyarn-lab-hero.webp")
    end
  end

  def seo_published_time(assigns) do
    case assigns[:seo_published_on] do
      %Date{} = date -> Date.to_iso8601(date)
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  def seo_modified_time(assigns) do
    case assigns[:seo_modified_on] do
      %Date{} = date -> Date.to_iso8601(date)
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  def seo_article_tags(assigns) do
    case assigns[:seo_article_tags] do
      tags when is_list(tags) -> Enum.filter(tags, &is_binary/1)
      _ -> []
    end
  end

  def seo_robots(assigns) do
    cond do
      Application.get_env(:storyarn, :noindex, false) ->
        "noindex, nofollow"

      is_binary(assigns[:seo_robots]) and String.trim(assigns[:seo_robots]) != "" ->
        String.trim(assigns[:seo_robots])

      non_indexable_path?(current_request_path(assigns)) ->
        "noindex, follow"

      true ->
        nil
    end
  end

  def seo_alternate_links(assigns) do
    case assigns[:seo_alternate_links] do
      links when is_list(links) ->
        links
        |> Enum.map(&normalize_alternate_link/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.hreflang)

      _other ->
        []
    end
  end

  def seo_json_ld(assigns) do
    case assigns[:seo_json_ld] do
      data when is_map(data) -> {:safe, data |> Jason.encode!() |> escape_json_ld()}
      _ -> nil
    end
  end

  @doc false
  def live_seo_metadata(assigns) do
    %{
      content_locale: content_locale(assigns),
      locale: seo_locale(assigns),
      title: seo_title(assigns),
      description: seo_description(assigns),
      canonical_url: explicit_canonical_url(assigns),
      type: seo_type(assigns),
      image_url: seo_image_url(assigns),
      published_time: seo_published_time(assigns),
      modified_time: seo_modified_time(assigns),
      article_tags: seo_article_tags(assigns),
      robots: seo_robots(assigns),
      alternate_links: seo_alternate_links(assigns),
      json_ld: seo_json_ld_data(assigns)
    }
  end

  attr :metadata, :map, required: true

  def live_seo(assigns) do
    ~H"""
    <div
      id="live-seo-metadata"
      phx-hook="SeoMetadata"
      data-metadata={Jason.encode!(@metadata)}
      hidden
      aria-hidden="true"
    >
    </div>
    """
  end

  defp seo_locale(assigns) do
    assigns |> content_locale() |> PublicLocales.language_tag()
  end

  defp content_locale(assigns) do
    case assigns[:locale] do
      locale when is_binary(locale) and locale != "" -> locale
      _ -> PublicLocales.default_locale()
    end
  end

  defp explicit_canonical_url(assigns) do
    case assigns[:canonical_url] do
      url when is_binary(url) and url != "" -> absolute_url(url)
      _ -> nil
    end
  end

  defp seo_json_ld_data(assigns) do
    case assigns[:seo_json_ld] do
      data when is_map(data) -> data
      _ -> nil
    end
  end

  defp normalize_alternate_link(%{hreflang: hreflang, href: href}) when is_binary(hreflang) and is_binary(href) do
    hreflang = String.trim(hreflang)
    href = String.trim(href)

    with true <- hreflang != "" and href != "",
         %URI{scheme: scheme, host: host} = uri when scheme in ["http", "https"] and host != nil <-
           href |> absolute_url() |> URI.parse() do
      normalized_href = URI.to_string(%{uri | query: nil, fragment: nil})
      %{hreflang: hreflang, href: normalized_href}
    else
      _other -> nil
    end
  end

  defp normalize_alternate_link(_link), do: nil

  defp current_scope_from_assigns(%{current_scope: current_scope}), do: current_scope

  defp current_scope_from_assigns(%{conn: %{assigns: %{current_scope: current_scope}}}) do
    current_scope
  end

  defp current_scope_from_assigns(%{socket: %{assigns: %{current_scope: current_scope}}}) do
    current_scope
  end

  defp current_scope_from_assigns(_assigns), do: nil

  defp current_request_path(%{conn: %{request_path: path}}) when is_binary(path), do: path
  defp current_request_path(_assigns), do: "/"

  defp non_indexable_path?(path) do
    String.starts_with?(path, "/users/") or
      String.starts_with?(path, "/workspaces") or
      String.starts_with?(path, "/projects/invitations/")
  end

  @doc false
  def absolute_url(path) do
    StoryarnWeb.Endpoint.url()
    |> URI.merge(path)
    |> URI.to_string()
  end

  defp escape_json_ld(json) do
    json
    |> String.replace("&", "\\u0026")
    |> String.replace("<", "\\u003c")
    |> String.replace(">", "\\u003e")
    |> String.replace("\u2028", "\\u2028")
    |> String.replace("\u2029", "\\u2029")
  end
end
