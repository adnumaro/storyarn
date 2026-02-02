defmodule Storyarn.PagesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  pages via the `Storyarn.Pages` context.
  """

  alias Storyarn.Pages
  alias Storyarn.ProjectsFixtures

  def unique_page_name, do: "Page #{System.unique_integer([:positive])}"

  def valid_page_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_page_name()
    })
  end

  @doc """
  Creates a page.
  """
  def page_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, page} =
      attrs
      |> valid_page_attributes()
      |> then(&Pages.create_page(project, &1))

    page
  end

  def unique_block_label, do: "Field #{System.unique_integer([:positive])}"

  @doc """
  Creates a block within a page.
  """
  def block_fixture(page, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        type: "text",
        config: %{"label" => unique_block_label(), "placeholder" => "Enter text..."},
        value: %{"content" => ""}
      })

    {:ok, block} = Pages.create_block(page, attrs)
    block
  end
end
