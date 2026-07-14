defmodule StoryarnWeb.LandingLive.Contact do
  @moduledoc false

  use StoryarnWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Contact"),
       seo_description:
         gettext(
           "Contact Storyarn about the narrative design platform for game writers, narrative designers, and game design teams."
         )
     )}
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
