defmodule StoryarnWeb.LandingLive.Contact do
  @moduledoc false

  use StoryarnWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Contact"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash} socket={@socket} current_scope={@current_scope} theme="dark">
      <.vue
        v-component="live/public/contact/Page"
        v-socket={@socket}
        v-inject="public-layout"
        id="contact-page"
        class="flex flex-1 flex-col"
        contact-email={contact_email()}
      />
    </Layouts.public>
    """
  end

  defp contact_email do
    Application.fetch_env!(:storyarn, :contact_email)
  end
end
