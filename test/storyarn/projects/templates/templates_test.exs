defmodule Storyarn.Projects.TemplatesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Templates

  test "exposes the template contract through the Project-owned capability boundary" do
    Code.ensure_loaded!(Templates)

    for {function, arity} <- [
          {:list_templates, 1},
          {:list_templates, 2},
          {:paginate_templates, 1},
          {:paginate_templates, 2},
          {:get_template, 2},
          {:get_template, 3},
          {:list_template_versions, 2},
          {:list_template_installs, 2},
          {:list_template_installs, 3},
          {:list_template_publications, 1},
          {:list_template_publications, 2},
          {:can_manage_template?, 2},
          {:can_publish_source_project?, 2},
          {:request_template_publication, 3},
          {:request_template_version_publication, 4},
          {:subscribe_template_publications, 1},
          {:archive_template, 2},
          {:unarchive_template, 2},
          {:delete_template, 2},
          {:request_template_instantiation, 4},
          {:list_active_workspace_installations, 2},
          {:list_pending_workspace_installation_failures, 2},
          {:list_pending_template_installation_failures, 2},
          {:dismiss_installation_failure, 3},
          {:list_active_template_installations, 2},
          {:subscribe_workspace_installations, 1},
          {:subscribe_user_installations, 1},
          {:preview_portable_template, 1},
          {:preview_portable_template, 2},
          {:import_portable_template, 1},
          {:import_portable_template, 2}
        ] do
      assert function_exported?(Templates, function, arity)
    end
  end
end
