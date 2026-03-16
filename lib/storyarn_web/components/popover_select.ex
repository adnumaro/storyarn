defmodule StoryarnWeb.Components.PopoverSelect do
  @moduledoc """
  Floating selector backed by the shared `SearchableSelect` hook.
  """

  use StoryarnWeb, :html

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :options, :list, required: true
  attr :param_key, :string, default: "value"
  attr :selected_value, :string, default: nil
  attr :selected_label, :string, default: nil
  attr :placeholder, :string, required: true
  attr :searchable, :boolean, default: false
  attr :search_placeholder, :string, default: nil
  attr :empty_label, :string, default: nil

  attr :button_class, :string,
    default:
      "btn btn-ghost btn-sm min-w-40 justify-between border border-base-300 bg-base-100 font-normal"

  def popover_select(assigns) do
    assigns =
      assigns
      |> assign_new(:search_placeholder, fn -> gettext("Search...") end)
      |> assign_new(:empty_label, fn -> gettext("No matches") end)
      |> assign(:options_with_params, build_options(assigns))

    ~H"""
    <div id={@id} phx-hook="SearchableSelect">
      <button data-role="trigger" type="button" class={@button_class}>
        <span class="min-w-0 truncate text-sm">{@selected_label || @placeholder}</span>
        <.icon name="chevron-down" class="size-3 shrink-0 opacity-50" />
      </button>

      <template data-role="popover-template">
        <div :if={@searchable} class="p-2 pb-1">
          <input
            data-role="search"
            type="text"
            placeholder={@search_placeholder}
            class="input input-xs input-bordered w-full"
            autocomplete="off"
          />
        </div>

        <div data-role="list" class="max-h-56 overflow-y-auto p-1">
          <button
            :for={option <- @options_with_params}
            type="button"
            data-event={@event}
            data-params={option.params}
            data-search-text={option.search_text}
            class={[
              "flex w-full items-center rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10",
              to_string(option.value) == to_string(@selected_value) &&
                "bg-base-content/10 font-semibold text-primary"
            ]}
          >
            {option.label}
          </button>
        </div>

        <div
          data-role="empty"
          class="px-3 py-2 text-xs italic text-base-content/40"
          style="display:none"
        >
          {@empty_label}
        </div>
      </template>
    </div>
    """
  end

  defp build_options(assigns) do
    Enum.map(assigns.options, fn {label, value} ->
      %{
        label: label,
        value: value,
        params: Jason.encode!(%{assigns.param_key => value}),
        search_text: String.downcase(label)
      }
    end)
  end
end
