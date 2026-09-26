defmodule Mix.Tasks.Convention.CheckTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Convention.Check, as: ConventionCheck

  @tag :tmp_dir
  test "an injected <.vue> page may not carry layout classes; its PageContainer owns layout", %{tmp_dir: tmp_dir} do
    web = Path.join(tmp_dir, "storyarn_web")
    File.mkdir_p!(web)

    bad =
      write(web, "bad.ex", """
      ~H\"\"\"
      <.vue
        v-component="live/workspace/dashboard/WorkspaceDashboard"
        v-socket={@socket}
        v-inject="workspace-layout"
        workspace={%{name: @workspace.name, "size" => 1}}
        class="container mx-auto h-full"
      />
      \"\"\"
      """)

    output = capture_io(fn -> assert_raise Mix.Error, fn -> ConventionCheck.run([bad]) end end)
    assert output =~ "vue_tag_layout"
    assert output =~ "bad.ex:7"
    assert output =~ "(container mx-auto)"

    allowed =
      write(web, "allowed.ex", """
      ~H\"\"\"
      <.vue v-component="live/sheet/show/SheetSurface" v-inject="project-layout" class="contents" />
      <.vue v-component="live/scene/show/SceneCompactSurface" v-inject="compare" class="h-full relative" />
      <.vue v-component="live/flow/show/FlowSurface" v-inject="project-layout" class="w-full h-full" />
      <.vue v-component="live/public/contact/PublicContact" class="flex flex-1 flex-col" />
      \"\"\"
      """)

    assert capture_io(fn -> ConventionCheck.run([allowed]) end) =~ "No convention violations"

    suppressed =
      write(web, "suppressed.ex", """
      ~H\"\"\"
      <.vue
        v-component="live/workspace/dashboard/WorkspaceDashboard"
        v-inject="workspace-layout"
        # storyarn:disable:vue_tag_layout
        class="mx-auto"
      />
      \"\"\"
      """)

    assert capture_io(fn -> ConventionCheck.run([suppressed]) end) =~ "No convention violations"
  end

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end
end
