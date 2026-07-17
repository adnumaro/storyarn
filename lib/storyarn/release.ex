defmodule Storyarn.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Storyarn.ProjectTemplates.LegacySnapshotRepair

  @app :storyarn
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @project_roles ~w(editor viewer)
  @workspace_roles ~w(admin member viewer)

  @template_import_option_keys %{
    "description" => :description,
    "name" => :name,
    "owner_id" => :owner_id,
    "published_by_id" => :published_by_id,
    "repair_legacy_snapshot" => :repair_legacy_snapshot,
    "slug" => :slug,
    "update_existing" => :update_existing,
    "verify_user_id" => :verify_user_id,
    "verify_workspace_id" => :verify_workspace_id,
    "version_notes" => :version_notes,
    "visibility" => :visibility,
    description: :description,
    name: :name,
    owner_id: :owner_id,
    published_by_id: :published_by_id,
    repair_legacy_snapshot: :repair_legacy_snapshot,
    slug: :slug,
    update_existing: :update_existing,
    verify_user_id: :verify_user_id,
    verify_workspace_id: :verify_workspace_id,
    version_notes: :version_notes,
    visibility: :visibility
  }

  @doc """
  Create a member invitation from a release node.

  Creates an invitation record and queues the invitation email for delivery.
  The invitee must click the acceptance link to create their account and join.

  Usage from Fly SSH (uses rpc to run inside the live node):
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"user@example.com\\", \\"project\\", 123, \\"editor\\", \\"es\\", \\"requester@example.com\\")"'
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"user@example.com\\", \\"workspace\\", 456, \\"member\\", \\"en\\", \\"requester@example.com\\")"'
  """
  def invite_member(email, type, entity_id, role, locale \\ "en", inviter_name \\ "Storyarn")
      when is_binary(email) and type in ["project", "workspace"] do
    allowed_roles = if type == "project", do: @project_roles, else: @workspace_roles

    if role not in allowed_roles do
      raise ArgumentError,
            "Invalid role #{inspect(role)} for #{type}. Allowed: #{inspect(allowed_roles)}"
    end

    Gettext.put_locale(Storyarn.Gettext, locale)

    email = String.downcase(email)

    {context_module, entity} = invitation_config(type, entity_id)

    case context_module.create_admin_invitation(entity, email, role, inviter_name: inviter_name) do
      {:ok, _invitation} ->
        IO.puts("Invitation created and email queued for #{email} as #{role} to #{type} ##{entity_id}")

      {:error, :already_member} ->
        IO.puts("#{email} is already a member of this #{type}")

      {:error, :already_invited} ->
        IO.puts("#{email} already has a pending invitation for this #{type}")

      {:error, :limit_reached, details} ->
        IO.puts("Failed to create invitation: member limit reached (#{inspect(details)})")
        raise "Cannot create invitation: member limit reached"

      {:error, reason} ->
        IO.puts("Failed to create invitation: #{inspect(reason)}")
        raise "Cannot create invitation: #{inspect(reason)}"
    end
  end

  @doc """
  Preview a portable project template bundle from a release node.

  Usage from Fly SSH after the bundle is present on the machine:

      fly ssh console -a storyarn -C '/app/bin/storyarn rpc "Storyarn.Release.preview_template_bundle(\\"/tmp/veilbreak.storyarn-template.tar.gz\\")"'
  """
  def preview_template_bundle(path) when is_binary(path) do
    load_app()

    case Storyarn.ProjectTemplates.preview_portable_template(path) do
      {:ok, manifest} ->
        print_template_bundle_preview(path, manifest, [])
        manifest

      {:error, reason} ->
        raise "Could not read template bundle: #{inspect(reason)}"
    end
  end

  @doc """
  Import a portable project template bundle from a release node.

  `opts` must be a map with only known import options. For a public demo import,
  pass at least `visibility`, `verify_user_id`, and `verify_workspace_id`.

  Usage from Fly SSH after the bundle is present on the machine:

      fly ssh console -a storyarn -C '/app/bin/storyarn rpc "Storyarn.Release.import_template_bundle(\\"/tmp/veilbreak.storyarn-template.tar.gz\\", %{visibility: \\"public\\", verify_user_id: 123, verify_workspace_id: 456, update_existing: true})"'
  """
  def import_template_bundle(path, opts \\ %{}) when is_binary(path) and is_map(opts) do
    load_app()

    with {:ok, keyword_opts} <- template_import_options(opts),
         {:ok, manifest} <- Storyarn.ProjectTemplates.preview_portable_template(path, keyword_opts) do
      print_template_bundle_preview(path, manifest, keyword_opts)

      case Storyarn.ProjectTemplates.import_portable_template(path, keyword_opts) do
        {:ok, template} ->
          IO.puts("Imported template ##{template.id}: #{template.name}")
          IO.puts("Visibility: #{template.visibility}")
          IO.puts("Current version: #{template.current_version_id}")
          IO.puts("Editable source project: #{template.source_project_id}")
          template

        {:error, reason} ->
          raise "Could not import template bundle: #{inspect(reason)}"
      end
    else
      {:error, reason} ->
        raise "Could not import template bundle: #{inspect(reason)}"
    end
  end

  defp invitation_config("project", id) do
    {Storyarn.Projects, Storyarn.Projects.get_project!(id)}
  end

  defp invitation_config("workspace", id) do
    {Storyarn.Workspaces, Storyarn.Workspaces.get_workspace!(id)}
  end

  defp template_import_options(opts) do
    Enum.reduce_while(opts, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case Map.fetch(@template_import_option_keys, key) do
        {:ok, option_key} -> {:cont, {:ok, Keyword.put(acc, option_key, value)}}
        :error -> {:halt, {:error, {:invalid_template_import_option, key}}}
      end
    end)
  end

  defp print_template_bundle_preview(path, manifest, opts) do
    template = manifest["template"] || %{}
    repair_lines = template_repair_preview_lines!(manifest["legacy_snapshot_repair"])

    IO.puts("Template bundle: #{path}")
    IO.puts("Name: #{Keyword.get(opts, :name) || template["name"]}")
    IO.puts("Slug: #{Keyword.get(opts, :slug) || template["slug"]}")
    IO.puts("Visibility: #{Keyword.get(opts, :visibility, "private")}")
    IO.puts("Verify user ID: #{Keyword.get(opts, :verify_user_id) || "missing"}")
    IO.puts("Verify workspace ID: #{Keyword.get(opts, :verify_workspace_id) || "missing"}")
    IO.puts("Repair legacy snapshot: #{Keyword.get(opts, :repair_legacy_snapshot, false)}")
    Enum.each(repair_lines, &IO.puts/1)
    IO.puts("Assets: #{manifest["asset_count"]}")
    IO.puts("Checksum: #{manifest["checksum"]}")
  end

  defp template_repair_preview_lines!(report) do
    case LegacySnapshotRepair.preview_lines(report) do
      {:ok, lines} -> lines
      {:error, reason} -> raise "Could not read template bundle: #{inspect(reason)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
