defmodule Mix.Tasks.Storyarn.Templates.Export do
  @shortdoc "Exports a project as a portable template bundle"
  @moduledoc """
  Exports a project as a portable template bundle.

      mix storyarn.templates.export PROJECT_ID --output /tmp/veilbreak.storyarn-template.tar.gz

  Optional flags:

    * `--name`
    * `--slug`
    * `--description`
    * `--version-notes`

  The export runs the same template audit used by normal publication and embeds
  every referenced asset blob needed to import the template in another deployment.
  """

  use Mix.Task

  alias Storyarn.ProjectTemplates

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          output: :string,
          name: :string,
          slug: :string,
          description: :string,
          version_notes: :string
        ],
        aliases: [o: :output]
      )

    {project_id, output_path} = parse_args!(positional, opts)

    case ProjectTemplates.export_portable_template(project_id, output_path, opts) do
      {:ok, %{manifest: manifest, path: path}} ->
        Mix.shell().info("Exported template bundle: #{path}")
        Mix.shell().info("Name: #{get_in(manifest, ["template", "name"])}")
        Mix.shell().info("Slug: #{get_in(manifest, ["template", "slug"])}")
        Mix.shell().info("Assets: #{manifest["asset_count"]}")
        Mix.shell().info("Checksum: #{manifest["checksum"]}")

      {:error, {:audit_failed, report}} ->
        Mix.raise("Template audit failed:\n#{Jason.encode!(report, pretty: true)}")

      {:error, reason} ->
        Mix.raise("Could not export template bundle: #{inspect(reason)}")
    end
  end

  defp parse_args!([project_id], opts) do
    output_path = Keyword.get(opts, :output) || Mix.raise("Missing required --output path.")

    case Integer.parse(project_id) do
      {integer, ""} when integer > 0 -> {integer, output_path}
      _other -> Mix.raise("PROJECT_ID must be a positive integer.")
    end
  end

  defp parse_args!(_positional, _opts) do
    Mix.raise("Usage: mix storyarn.templates.export PROJECT_ID --output PATH")
  end
end
