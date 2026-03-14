defmodule StoryarnWeb.Components.LandingPage.LandingFooter do
  @moduledoc """
  Footer for the landing page.
  """
  use StoryarnWeb, :html

  def landing_footer(assigns) do
    ~H"""
    <footer class="pb-8">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)] flex flex-col sm:flex-row justify-between gap-5 text-base-content/50 text-sm">
        <span>{gettext("Storyarn - Open narrative design platform")}</span>
        <div class="flex gap-6">
          <.link navigate={~p"/docs"} class="hover:text-base-content transition-colors">
            {gettext("Docs")}
          </.link>
          <.link navigate={~p"/contact"} class="hover:text-base-content transition-colors">
            {gettext("Contact")}
          </.link>
        </div>
      </div>
    </footer>
    """
  end
end
