defmodule StoryarnWeb.Components.LanguagePicker do
  @moduledoc """
  Searchable language picker backed by the `SearchableSelect` hook.
  """

  use StoryarnWeb, :html

  alias Storyarn.Localization
  alias StoryarnWeb.Components.LocaleMark

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :options, :list, required: true
  attr :param_key, :string, default: "locale_code"
  attr :selected_label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :search_placeholder, :string, default: nil
  attr :empty_label, :string, default: nil
  attr :button_icon, :string, default: "languages"

  attr :button_class, :string,
    default:
      "btn btn-ghost btn-sm w-full justify-between border border-base-300 bg-base-100 font-normal"

  attr :disabled, :boolean, default: false

  def language_picker(assigns) do
    assigns =
      assigns
      |> assign_new(:placeholder, fn -> dgettext("localization", "Select language...") end)
      |> assign_new(:search_placeholder, fn ->
        dgettext("localization", "Search languages...")
      end)
      |> assign_new(:empty_label, fn -> dgettext("localization", "No matches") end)
      |> assign(:options_with_params, build_options(assigns))

    ~H"""
    <div id={@id} phx-hook="SearchableSelect">
      <button
        data-role="trigger"
        type="button"
        class={@button_class}
        disabled={@disabled}
      >
        <span class="flex min-w-0 items-center gap-2">
          <.icon name={@button_icon} class="size-4 shrink-0" />
          <span :if={@selected_label} class="truncate text-sm">{@selected_label}</span>
          <span :if={!@selected_label} class="truncate text-sm">{@placeholder}</span>
        </span>
        <.icon name="chevron-down" class="size-3 opacity-50 shrink-0" />
      </button>

      <template data-role="popover-template">
        <div class="p-2 pb-1">
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
            class="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
          >
            <LocaleMark.locale_mark locale_code={option.value} class="h-4 w-4 text-[0.7rem]" />
            <span class="min-w-0 truncate">{option.label}</span>
          </button>
        </div>
        <div
          data-role="empty"
          class="px-3 py-2 text-xs text-base-content/40 italic"
          style="display:none"
        >
          {@empty_label}
        </div>
      </template>
    </div>
    """
  end

  @spec source_language_options(map() | nil) :: list({String.t(), String.t()})
  def source_language_options(nil), do: Localization.language_options_for_select()

  def source_language_options(%{locale_code: locale_code}) when is_binary(locale_code) do
    Localization.language_options_for_select(exclude: [locale_code])
  end

  def source_language_options(_source_language), do: Localization.language_options_for_select()

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
