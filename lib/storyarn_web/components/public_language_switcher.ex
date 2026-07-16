defmodule StoryarnWeb.Components.PublicLanguageSwitcher do
  @moduledoc false

  use StoryarnWeb, :html

  alias Phoenix.LiveView.JS
  alias Storyarn.Localization.Languages

  attr :id, :string, required: true
  attr :current_locale, :string, required: true
  attr :links, :list, required: true
  attr :compact, :boolean, default: false
  attr :on_navigate, :any, default: nil

  def switcher(assigns) do
    links = Enum.map(assigns.links, &with_language_metadata/1)
    current_link = Enum.find(links, &(&1.locale == assigns.current_locale))
    page_language_label = dgettext("public", "Page language")
    close = JS.remove_attribute("open", to: "##{assigns.id}")

    trigger_label =
      if current_link,
        do: "#{page_language_label}: #{current_link.label}",
        else: page_language_label

    assigns =
      assigns
      |> assign(:links, links)
      |> assign(:current_link, current_link)
      |> assign(:trigger_label, trigger_label)
      |> assign(:close, close)
      |> assign(:close_and_focus, JS.focus(close, to: "##{assigns.id}-trigger"))
      |> assign(:visible?, length(links) > 1)

    ~H"""
    <details
      :if={@visible?}
      id={@id}
      class={[
        "group relative",
        if(@compact, do: "inline-block", else: "block w-full")
      ]}
      phx-click-away={@close}
      phx-window-keydown={@close_and_focus}
      phx-key="Escape"
    >
      <summary
        id={"#{@id}-trigger"}
        aria-label={@trigger_label}
        title={@current_link && @current_link.label}
        class={[
          "inline-flex min-h-8 list-none items-center justify-between gap-2 rounded-full border border-border bg-background px-2.5 text-sm font-medium text-foreground shadow-xs transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50",
          @compact && "text-xs uppercase tracking-wide",
          !@compact && "w-full min-h-10 rounded-md px-3"
        ]}
      >
        <span class="flex min-w-0 items-center gap-2">
          <.language_flag
            :if={@current_link}
            link={@current_link}
            size={if @compact, do: "size-4", else: "size-5"}
          />
          <span class="truncate">
            {if(@compact,
              do: @current_link && @current_link.short_label,
              else: @current_link && @current_link.label
            )}
          </span>
        </span>
        <.icon
          name="chevron-down"
          class="size-3.5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180"
        />
      </summary>

      <ul
        aria-label={dgettext("public", "Page language")}
        class={[
          "absolute top-full z-50 mt-2 min-w-56 rounded-md border border-border bg-popover p-1.5 text-popover-foreground shadow-md",
          if(@compact, do: "right-0", else: "inset-x-0 w-full")
        ]}
      >
        <%= for link <- @links do %>
          <li>
            <span
              :if={link.locale == @current_locale}
              id={"#{@id}-#{link.locale}"}
              lang={link.language_tag}
              aria-current="page"
              class="flex min-h-10 items-center gap-2.5 rounded-md bg-accent px-2.5 py-2 text-sm font-medium text-accent-foreground"
            >
              <.language_flag link={link} />
              <span class="min-w-0 flex-1 truncate">{link.label}</span>
              <.icon name="check" class="size-4 shrink-0 text-primary" />
            </span>
            <.link
              :if={link.locale != @current_locale}
              id={"#{@id}-#{link.locale}"}
              navigate={link.path}
              hreflang={link.language_tag}
              lang={link.language_tag}
              title={link.label}
              phx-click={@on_navigate}
              class="flex min-h-10 items-center gap-2.5 rounded-md px-2.5 py-2 text-sm font-medium text-foreground/80 outline-none transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:bg-accent focus-visible:text-accent-foreground"
            >
              <.language_flag link={link} />
              <span class="min-w-0 flex-1 truncate">{link.label}</span>
              <span class="text-[0.68rem] font-medium uppercase text-muted-foreground">
                {link.short_label}
              </span>
            </.link>
          </li>
        <% end %>
      </ul>
    </details>
    """
  end

  attr :link, :map, required: true
  attr :size, :string, default: "size-5"

  defp language_flag(assigns) do
    ~H"""
    <span
      aria-hidden="true"
      class={[
        "storyarn-language-flag relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full border border-black/10 bg-muted text-[0.62rem] font-bold uppercase leading-none tracking-wide shadow-sm dark:border-white/10",
        @size
      ]}
    >
      <span class="storyarn-language-flag-label">{@link.short_label}</span>
      <span
        :if={@link.flag_code}
        class={["fi fis absolute inset-0 size-full", "fi-#{@link.flag_code}"]}
      />
    </span>
    """
  end

  defp with_language_metadata(link) do
    locale = link.language_tag || link.locale

    link
    |> Map.put(:flag_code, Languages.flag_code(locale))
    |> Map.put(:short_label, Languages.short_label(locale))
  end
end
