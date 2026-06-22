defmodule StoryarnWeb.LegalLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  @controller_address "Grådybet 73B, 6700 Esbjerg, Denmark"
  @controller_name "Adrián Nuhacet Martin Rodriguez"
  @updated_at "2026-06-21"

  @impl true
  def mount(_params, _session, socket) do
    document = legal_document(socket.assigns.live_action)

    {:ok,
     socket
     |> assign(:page_title, document.title)
     |> assign(:document, document.key)
     |> assign(:updated_at, @updated_at)
     |> assign(:controller_address, @controller_address)
     |> assign(:controller_name, @controller_name)
     |> assign(:contact_email, contact_email())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      theme="dark"
    >
      <.vue
        v-component="live/public/legal/LegalPage"
        v-socket={@socket}
        v-inject="public-layout"
        id={"legal-#{@document}-page"}
        class="flex flex-1 flex-col"
        document={@document}
        updated-at={@updated_at}
        controller-address={@controller_address}
        controller-name={@controller_name}
        contact-email={@contact_email}
      />
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp legal_document(:terms), do: %{key: "terms", title: gettext("Terms of Use")}
  defp legal_document(_privacy), do: %{key: "privacy", title: gettext("Privacy Policy")}

  defp contact_email do
    Application.fetch_env!(:storyarn, :contact_email)
  end
end
