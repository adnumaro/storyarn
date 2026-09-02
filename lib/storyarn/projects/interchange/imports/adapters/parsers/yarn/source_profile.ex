defmodule Storyarn.Projects.Imports.Parsers.Yarn.SourceProfile do
  @moduledoc """
  Owns the accepted Yarn upload shapes and turns them into a parser-safe bundle.

  `SourceBundle` provides the format-neutral security boundary. This module
  supplies Yarn's extensions, `.yarnproject` selection semantics, required
  source rule, and whole-project replacement eligibility.
  """

  alias Storyarn.Projects.Imports.Parsers.Yarn.ProjectSources
  alias Storyarn.Projects.Imports.SourceBundle

  @plain_extensions MapSet.new([".yarn"])
  @archive_extensions MapSet.new([".zip"])
  @archive_entry_extensions MapSet.new([".yarn", ".yarnproject", ".csv", ".json"])

  @profile %{
    plain_extensions: @plain_extensions,
    archive_extensions: @archive_extensions,
    archive_entry_extensions: @archive_entry_extensions
  }

  @spec open(String.t(), binary()) :: {:ok, SourceBundle.t()} | {:error, atom()}
  def open(filename, binary) when is_binary(filename) and is_binary(binary) do
    with {:ok, bundle} <-
           SourceBundle.open(filename, binary, @profile, &ProjectSources.select/1),
         :ok <- require_yarn(bundle) do
      {:ok, bundle}
    end
  end

  @spec yarn_files(SourceBundle.t()) :: [SourceBundle.source_file()]
  def yarn_files(%SourceBundle{files: files}) do
    Enum.filter(files, &(&1.extension == ".yarn"))
  end

  @spec replace_eligible?(SourceBundle.t()) :: boolean()
  def replace_eligible?(%SourceBundle{kind: :archive, files: files}) do
    Enum.any?(files, &(&1.extension == ".yarnproject"))
  end

  def replace_eligible?(%SourceBundle{}), do: false

  defp require_yarn(bundle) do
    if yarn_files(bundle) == [],
      do: {:error, :archive_missing_yarn_files},
      else: :ok
  end
end
