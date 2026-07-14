defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS
  alias Storyarn.Analytics

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} socket={@socket} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue events)"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

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
        privacy-url={~p"/privacy#cookies"}
        terms-url={~p"/terms"}
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

  def seo_json_ld(assigns) do
    case assigns[:seo_json_ld] do
      data when is_map(data) -> {:safe, data |> Jason.encode!() |> escape_json_ld()}
      _ -> nil
    end
  end

  @doc false
  def live_seo_metadata(assigns) do
    %{
      locale: seo_locale(assigns),
      title: seo_title(assigns),
      description: seo_description(assigns),
      canonical_url: explicit_canonical_url(assigns),
      type: seo_type(assigns),
      image_url: seo_image_url(assigns),
      published_time: seo_published_time(assigns),
      modified_time: seo_modified_time(assigns),
      article_tags: seo_article_tags(assigns),
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
    case assigns[:locale] do
      locale when is_binary(locale) and locale != "" -> locale
      _ -> "en"
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
