defmodule StoryarnWeb.Components.PublicLanguageSwitcher do
  @moduledoc false

  use StoryarnWeb, :html

  attr :id, :string, required: true
  attr :current_locale, :string, required: true
  attr :links, :list, required: true
  attr :compact, :boolean, default: false
  attr :on_navigate, :any, default: nil

  def switcher(assigns) do
    assigns = assign(assigns, :visible?, length(assigns.links) > 1)

    ~H"""
    <nav
      :if={@visible?}
      id={@id}
      class="inline-flex items-center rounded-full border border-border/80 bg-background/70 p-1 shadow-sm backdrop-blur"
      aria-label={dgettext("public", "Page language")}
    >
      <%= for link <- @links do %>
        <span
          :if={link.locale == @current_locale}
          id={"#{@id}-#{link.locale}"}
          lang={link.language_tag}
          aria-current="page"
          aria-label={@compact && link.label}
          title={link.label}
          class={[
            "rounded-full bg-primary px-3 py-1.5 text-xs font-semibold text-primary-foreground shadow-sm",
            @compact && "uppercase"
          ]}
        >
          {if(@compact, do: link.language_tag, else: link.label)}
        </span>
        <.link
          :if={link.locale != @current_locale}
          id={"#{@id}-#{link.locale}"}
          navigate={link.path}
          hreflang={link.language_tag}
          lang={link.language_tag}
          aria-label={@compact && link.label}
          title={link.label}
          phx-click={@on_navigate}
          class={[
            "rounded-full px-3 py-1.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
            @compact && "uppercase"
          ]}
        >
          {if(@compact, do: link.language_tag, else: link.label)}
        </.link>
      <% end %>
    </nav>
    """
  end
end
