defmodule StoryarnWeb.Components.LocaleMark do
  @moduledoc false

  use StoryarnWeb, :html

  alias Storyarn.Localization.Languages

  attr :locale_code, :string, required: true
  attr :class, :string, default: nil

  def locale_mark(assigns) do
    assigns =
      assigns
      |> assign(:flag_code, Languages.flag_code(assigns.locale_code))
      |> assign(:short_label, Languages.short_label(assigns.locale_code))

    ~H"""
    <%= if @flag_code do %>
      <img
        src={flag_path(@flag_code)}
        alt=""
        aria-hidden="true"
        class={["h-5 w-5 shrink-0 rounded-full object-cover", @class]}
        title={@locale_code}
      />
    <% else %>
      <span
        class={[
          "inline-flex min-w-[1.75rem] shrink-0 items-center justify-center text-[0.72rem] font-semibold uppercase leading-none tracking-[0.08em]",
          @class
        ]}
        title={@locale_code}
        aria-label={@locale_code}
      >
        {@short_label}
      </span>
    <% end %>
    """
  end

  defp flag_path(flag_code), do: "/images/flags/1x1/#{flag_code}.svg"
end
