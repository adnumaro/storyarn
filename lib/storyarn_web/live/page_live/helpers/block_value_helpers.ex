defmodule StoryarnWeb.PageLive.Helpers.BlockValueHelpers do
  @moduledoc """
  Value-returning block helpers for LiveComponent usage.

  These functions return {:ok, blocks} or {:error, message} instead of
  {:noreply, socket}, for use in LiveComponents that manage their own state.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Pages
  alias StoryarnWeb.PageLive.Helpers.ReferenceHelpers

  @doc """
  Toggles a multi-select option.
  Returns {:ok, blocks} or {:error, message}.
  """
  def toggle_multi_select_value(socket, block_id, key) do
    block_id = parse_id(block_id)
    project_id = socket.assigns.project.id
    page_id = socket.assigns.page.id
    block = Pages.get_block_in_project!(block_id, project_id)
    current = get_in(block.value, ["content"]) || []

    new_content =
      if key in current do
        List.delete(current, key)
      else
        [key | current]
      end

    case Pages.update_block_value(block, %{"content" => new_content}) do
      {:ok, _block} ->
        blocks = ReferenceHelpers.load_blocks_with_references(page_id, project_id)
        {:ok, blocks}

      {:error, _} ->
        {:error, gettext("Could not update multi-select.")}
    end
  end

  @doc """
  Handles multi-select Enter key to add new option.
  Returns {:ok, blocks} or {:error, message}.
  """
  def handle_multi_select_enter_value(socket, block_id, value) do
    value = String.trim(value)

    if value == "" do
      blocks =
        ReferenceHelpers.load_blocks_with_references(
          socket.assigns.page.id,
          socket.assigns.project.id
        )

      {:ok, blocks}
    else
      add_multi_select_option_value(socket, block_id, value)
    end
  end

  @doc """
  Updates rich text content.
  Returns {:ok, blocks} or {:error, message}.
  """
  def update_rich_text_value(socket, block_id, content) do
    block_id = parse_id(block_id)
    project_id = socket.assigns.project.id
    page_id = socket.assigns.page.id
    block = Pages.get_block_in_project!(block_id, project_id)

    case Pages.update_block_value(block, %{"content" => content}) do
      {:ok, _block} ->
        blocks = ReferenceHelpers.load_blocks_with_references(page_id, project_id)
        {:ok, blocks}

      {:error, _} ->
        {:error, gettext("Could not update content.")}
    end
  end

  @doc """
  Sets a boolean block value.
  Returns {:ok, blocks} or {:error, message}.
  """
  def set_boolean_block_value(socket, block_id, value_string) do
    block_id = parse_id(block_id)
    project_id = socket.assigns.project.id
    page_id = socket.assigns.page.id
    block = Pages.get_block_in_project!(block_id, project_id)

    new_value =
      case value_string do
        "true" -> true
        "false" -> false
        "null" -> nil
        _ -> nil
      end

    case Pages.update_block_value(block, %{"content" => new_value}) do
      {:ok, _block} ->
        blocks = ReferenceHelpers.load_blocks_with_references(page_id, project_id)
        {:ok, blocks}

      {:error, _} ->
        {:error, gettext("Could not update boolean value.")}
    end
  end

  # Private helpers

  defp add_multi_select_option_value(socket, block_id, value) do
    block_id = parse_id(block_id)
    project_id = socket.assigns.project.id
    page_id = socket.assigns.page.id
    block = Pages.get_block_in_project!(block_id, project_id)

    key = generate_option_key(value)
    current_options = get_in(block.config, ["options"]) || []
    current_content = get_in(block.value, ["content"]) || []

    existing =
      Enum.find(current_options, fn opt ->
        opt["key"] == key || String.downcase(opt["value"] || "") == String.downcase(value)
      end)

    if existing do
      if existing["key"] in current_content do
        blocks = ReferenceHelpers.load_blocks_with_references(page_id, project_id)
        {:ok, blocks}
      else
        new_content = [existing["key"] | current_content]

        case Pages.update_block_value(block, %{"content" => new_content}) do
          {:ok, _} ->
            blocks = ReferenceHelpers.load_blocks_with_references(page_id, project_id)
            {:ok, blocks}

          {:error, _} ->
            {:error, gettext("Could not update multi-select.")}
        end
      end
    else
      new_option = %{"key" => key, "value" => value}
      new_options = current_options ++ [new_option]
      new_content = [key | current_content]

      with {:ok, _} <-
             Pages.update_block_config(block, %{
               "options" => new_options,
               "label" => block.config["label"] || ""
             }),
           block <- Pages.get_block_in_project!(block_id, project_id),
           {:ok, _} <- Pages.update_block_value(block, %{"content" => new_content}) do
        blocks = ReferenceHelpers.load_blocks_with_references(page_id, project_id)
        {:ok, blocks}
      else
        _ -> {:error, gettext("Could not add option.")}
      end
    end
  end

  defp generate_option_key(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(fn key ->
      if key == "", do: "option-#{:rand.uniform(9999)}", else: key
    end)
  end

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id) when is_integer(id), do: id
end
