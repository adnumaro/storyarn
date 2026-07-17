defmodule Mix.Tasks.Storyarn.Templates.Import do
  @shortdoc "Imports a portable template bundle"
  @moduledoc """
  Imports a portable template bundle.

      mix storyarn.templates.import /tmp/veilbreak.storyarn-template.tar.gz \
        --visibility public \
        --verify-user-id 123 \
        --verify-workspace-id 456 \
        --yes

  Optional flags:

    * `--visibility private|public` defaults to `private`
    * `--owner-id USER_ID` required for private imports
    * `--published-by-id USER_ID`
    * `--verify-user-id USER_ID` required for materialization dry-run
    * `--verify-workspace-id WORKSPACE_ID` required for materialization dry-run
    * `--name`
    * `--slug`
    * `--description`
    * `--version-notes`
    * `--update-existing`
    * `--repair-legacy-snapshot` explicitly repairs the pre-sequence portable format
    * `--yes`

  `public` templates are intended for controlled admin/operator imports, not
  normal product UI.
  """

  use Mix.Task

  alias Storyarn.ProjectTemplates

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          visibility: :string,
          owner_id: :integer,
          published_by_id: :integer,
          verify_user_id: :integer,
          verify_workspace_id: :integer,
          name: :string,
          slug: :string,
          description: :string,
          version_notes: :string,
          update_existing: :boolean,
          repair_legacy_snapshot: :boolean,
          yes: :boolean
        ]
      )

    path = parse_args!(positional)

    case ProjectTemplates.preview_portable_template(path, opts) do
      {:ok, manifest} ->
        print_preview(path, manifest, opts)
        ensure_confirmed!(opts)

        case ProjectTemplates.import_portable_template(path, opts) do
          {:ok, template} ->
            Mix.shell().info("Imported template ##{template.id}: #{template.name}")
            Mix.shell().info("Visibility: #{template.visibility}")
            Mix.shell().info("Current version: #{template.current_version_id}")

          {:error, reason} ->
            Mix.raise("Could not import template bundle: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise("Could not read template bundle: #{inspect(reason)}")
    end
  end

  defp parse_args!([path]), do: path

  defp parse_args!(_positional) do
    Mix.raise(
      "Usage: mix storyarn.templates.import PATH --verify-user-id USER_ID --verify-workspace-id WORKSPACE_ID --yes"
    )
  end

  defp print_preview(path, manifest, opts) do
    template = manifest["template"] || %{}
    visibility = Keyword.get(opts, :visibility, "private")

    Mix.shell().info("Template bundle: #{path}")
    Mix.shell().info("Name: #{Keyword.get(opts, :name) || template["name"]}")
    Mix.shell().info("Slug: #{Keyword.get(opts, :slug) || template["slug"]}")
    Mix.shell().info("Visibility: #{visibility}")
    Mix.shell().info("Verify user ID: #{Keyword.get(opts, :verify_user_id) || "missing"}")
    Mix.shell().info("Verify workspace ID: #{Keyword.get(opts, :verify_workspace_id) || "missing"}")
    Mix.shell().info("Repair legacy snapshot: #{Keyword.get(opts, :repair_legacy_snapshot, false)}")
    print_repair_preview(manifest["legacy_snapshot_repair"])
    Mix.shell().info("Assets: #{manifest["asset_count"]}")
    Mix.shell().info("Checksum: #{manifest["checksum"]}")
  end

  defp print_repair_preview(nil), do: :ok

  defp print_repair_preview(report) do
    Mix.shell().info("Sequences replaced by recovery notes: #{report["repaired_sequence_count"]}")
    Mix.shell().info("Legacy localization rows removed: #{report["localization"]["removed_count"]}")
    Mix.shell().info("Warning: #{report["warning"]}")
  end

  defp ensure_confirmed!(opts) do
    if !Keyword.get(opts, :yes, false) do
      Mix.raise("Pass --yes to import this bundle.")
    end
  end
end
