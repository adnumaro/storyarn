defmodule StoryarnWeb.LandingLive.Contact do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias StoryarnWeb.PublicSEO

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    title = dgettext("public", "Contact")

    description =
      dgettext(
        "public",
        "Contact Storyarn about the narrative design platform for game writers, narrative designers, and game design teams."
      )

    {:noreply, assign(socket, PublicSEO.static_page_metadata(socket.assigns.locale, :contact, title, description))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :seo_metadata, Layouts.live_seo_metadata(assigns))

    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      seo_metadata={@seo_metadata}
      current_scope={@current_scope}
      language_links={@language_links}
      theme="dark"
    >
      <.vue
        v-component="live/public/contact/PublicContact"
        v-socket={@socket}
        id="contact-page"
        class="flex flex-1 flex-col"
        contact-email={contact_email()}
      />
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp contact_email do
    Application.fetch_env!(:storyarn, :contact_email)
  end
end
