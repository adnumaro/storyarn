defmodule StoryarnWeb.LegalLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias StoryarnWeb.PublicSEO
  alias StoryarnWeb.PublicURLs

  @controller_address "Grådybet 73B, 6700 Esbjerg, Denmark"
  @controller_name "Adrián Nuhacet Martin Rodriguez"
  @updated_at "2026-06-21"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:updated_at, @updated_at)
     |> assign(:controller_address, @controller_address)
     |> assign(:controller_name, @controller_name)
     |> assign(:contact_email, contact_email())}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    document = legal_document(socket.assigns.live_action)

    metadata =
      PublicSEO.static_page_metadata(
        socket.assigns.locale,
        document.page,
        document.title,
        document.description
      )

    {:noreply,
     socket
     |> assign(metadata)
     |> assign(:document, document.key)
     |> assign(:privacy_url, PublicURLs.privacy_path(socket.assigns.locale))}
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
        v-component="live/public/legal/LegalPage"
        v-socket={@socket}
        id={"legal-#{@document}-page"}
        class="flex flex-1 flex-col"
        document={@document}
        updated-at={@updated_at}
        controller-address={@controller_address}
        controller-name={@controller_name}
        contact-email={@contact_email}
        privacy-url={@privacy_url}
      />
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp legal_document(:terms) do
    %{
      page: :terms,
      key: "terms",
      title: dgettext("public", "Terms of Use"),
      description:
        dgettext(
          "public",
          "Terms of Use for Storyarn, the narrative design platform for game projects."
        )
    }
  end

  defp legal_document(_privacy) do
    %{
      page: :privacy,
      key: "privacy",
      title: dgettext("public", "Privacy Policy"),
      description:
        dgettext(
          "public",
          "Privacy Policy for Storyarn, including account, waitlist, invitation, and product analytics data."
        )
    }
  end

  defp contact_email do
    Application.fetch_env!(:storyarn, :contact_email)
  end
end
