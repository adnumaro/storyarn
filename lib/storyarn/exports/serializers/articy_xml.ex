defmodule Storyarn.Exports.Serializers.ArticyXML do
  @moduledoc """
  articy:draft compatible XML serializer.

  Produces XML that follows articy:draft's structure conventions with
  deterministic GUIDs generated from Storyarn UUIDs.

  ## Mapping

  | Storyarn       | articy:draft      |
  |----------------|-------------------|
  | Sheet          | Entity            |
  | Flow           | FlowFragment      |
  | Dialogue node  | DialogueFragment  |
  | Condition node | Condition element |
  | Instruction    | Instruction       |
  | Hub            | Hub               |
  | Jump           | Jump              |
  | Variable       | GlobalVariable    |
  | Connection     | Connection        |
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.{ExportOptions, ExpressionTranspiler}
  alias Storyarn.Exports.Serializers.Helpers

  # UUID v5 namespace for deterministic GUID generation
  @storyarn_namespace "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

  @impl true
  def content_type, do: "application/xml"

  @impl true
  def file_extension, do: "xml"

  @impl true
  def format_label, do: "articy:draft (XML)"

  @impl true
  def supported_sections, do: [:flows, :sheets]

  @impl true
  def serialize(project_data, %ExportOptions{} = opts) do
    sheets = project_data.sheets || []
    flows = project_data.flows || []
    variables = Helpers.collect_variables(sheets)
    speaker_map = Helpers.build_speaker_map(sheets)
    project = project_data.project

    project_guid = generate_guid("project:#{project.id}")
    project_tech = Helpers.shortcut_to_identifier(project.slug || "storyarn_project")

    xml =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>),
        ~s(<ArticyData>),
        ~s(  <Project Name="#{escape_xml(project.name)}" Guid="#{project_guid}" TechnicalName="#{project_tech}">),
        ~s(    <ExportSettings>),
        ~s(      <ExportVersion>1.0</ExportVersion>),
        ~s(      <StoryarnExportVersion>#{opts.version}</StoryarnExportVersion>),
        ~s(    </ExportSettings>),
        "",
        build_global_variables(variables),
        "",
        ~s(    <Hierarchy>),
        build_entities(sheets),
        build_flow_fragments(flows, speaker_map),
        ~s(    </Hierarchy>),
        ~s(  </Project>),
        ~s(</ArticyData>)
      ]
      |> List.flatten()
      |> Enum.join("\n")

    {:ok, xml}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Global Variables
  # ---------------------------------------------------------------------------

  defp build_global_variables([]), do: "    <GlobalVariables/>"

  defp build_global_variables(variables) do
    # Group by namespace (first part of sheet shortcut)
    namespaces =
      variables
      |> Enum.group_by(fn var ->
        var.sheet_shortcut
        |> String.split(".")
        |> List.first()
      end)
      |> Enum.sort_by(fn {ns, _} -> ns end)

    ns_xml =
      Enum.map(namespaces, fn {ns_name, vars} ->
        var_lines =
          Enum.map(vars, fn var ->
            articy_type = variable_type_to_articy(var.type)
            value = format_articy_value(var.default, var.type)
            # Variable name within namespace = everything after namespace prefix
            local_name = String.replace_prefix(var.full_ref, "#{ns_name}.", "")

            ~s(        <Variable Name="#{escape_xml(local_name)}" Type="#{articy_type}" Value="#{escape_xml(to_string(value))}"/>)
          end)

        [
          ~s(      <Namespace Name="#{escape_xml(ns_name)}">)
          | var_lines
        ] ++ [~s(      </Namespace>)]
      end)

    [~s(    <GlobalVariables>) | List.flatten(ns_xml)] ++ [~s(    </GlobalVariables>)]
  end

  defp variable_type_to_articy(:number), do: "int"
  defp variable_type_to_articy(:boolean), do: "bool"
  defp variable_type_to_articy(:string), do: "string"
  defp variable_type_to_articy(_), do: "string"

  defp format_articy_value(val, :boolean) when is_boolean(val), do: to_string(val)
  defp format_articy_value(val, :number) when is_number(val), do: to_string(val)
  defp format_articy_value(val, _) when is_binary(val), do: val
  defp format_articy_value(val, _), do: to_string(val)

  # ---------------------------------------------------------------------------
  # Entities (from Sheets)
  # ---------------------------------------------------------------------------

  defp build_entities(sheets) do
    Enum.map(sheets, fn sheet ->
      guid = generate_guid("entity:#{sheet.id}")

      properties =
        sheet.blocks
        |> Enum.reject(& &1.is_constant)
        |> Enum.filter(&(is_binary(&1.variable_name) and &1.variable_name != ""))
        |> Enum.map(fn block ->
          articy_type = variable_type_to_articy(Helpers.infer_variable_type(block))
          value = Helpers.infer_default_value(block)

          ~s(            <Property Name="#{escape_xml(block.variable_name)}" Type="#{articy_type}">#{escape_xml(to_string(value))}</Property>)
        end)

      prop_section =
        if properties == [] do
          [~s(          <Properties/>)]
        else
          [~s(          <Properties>) | properties] ++ [~s(          </Properties>)]
        end

      [
        ~s(      <Entity Type="Character" Id="#{guid}" TechnicalName="#{escape_xml(sheet.shortcut)}">),
        ~s(        <DisplayName>#{escape_xml(sheet.name)}</DisplayName>)
        | prop_section
      ] ++ [~s(      </Entity>)]
    end)
  end

  # ---------------------------------------------------------------------------
  # Flow Fragments (from Flows)
  # ---------------------------------------------------------------------------

  defp build_flow_fragments(flows, speaker_map) do
    Enum.map(flows, fn flow ->
      guid = generate_guid("flow:#{flow.id}")
      tech_name = flow.shortcut || flow.name || "flow_#{flow.id}"

      nodes_xml = build_flow_nodes(flow.nodes, speaker_map)
      connections_xml = build_connections(flow)

      [
        ~s(      <FlowFragment Type="Dialogue" Id="#{guid}" TechnicalName="#{escape_xml(tech_name)}">),
        ~s(        <DisplayName>#{escape_xml(flow.name)}</DisplayName>),
        ~s(        <Nodes>)
      ] ++
        List.flatten(nodes_xml) ++
        [~s(        </Nodes>), ~s(        <Connections>)] ++
        List.flatten(connections_xml) ++
        [~s(        </Connections>), ~s(      </FlowFragment>)]
    end)
  end

  defp build_flow_nodes(nodes, speaker_map) do
    Enum.map(nodes, fn node ->
      build_articy_node(node, speaker_map)
    end)
  end

  defp build_articy_node(%{type: "dialogue"} = node, speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    speaker = Helpers.speaker_shortcut(data, speaker_map) || ""
    text = Helpers.dialogue_text(data)
    menu_text = data["menu_text"] || ""
    stage = Helpers.strip_html(data["stage_directions"] || "")

    responses = Helpers.dialogue_responses(data)

    response_xml =
      Enum.map(responses, fn resp ->
        resp_guid = generate_guid("resp:#{resp["id"]}")
        resp_text = Helpers.strip_html(resp["text"] || "")

        resp_condition =
          case Helpers.extract_condition(resp["condition"]) do
            nil -> nil
            cond -> transpile_or_nil(cond, :articy, :condition)
          end

        cond_line =
          if resp_condition,
            do: [~s(            <Condition>#{escape_xml(resp_condition)}</Condition>)],
            else: []

        [
          ~s(          <DialogueFragment Id="#{resp_guid}" Speaker="" TechnicalName="resp_#{resp["id"]}">),
          ~s(            <Text>#{escape_xml(resp_text)}</Text>)
        ] ++
          cond_line ++
          [~s(          </DialogueFragment>)]
      end)

    [
      ~s(          <DialogueFragment Id="#{guid}" Speaker="#{escape_xml(speaker)}" TechnicalName="dlg_#{node.id}">),
      ~s(            <Text>#{escape_xml(text)}</Text>),
      ~s(            <MenuText>#{escape_xml(menu_text)}</MenuText>),
      ~s(            <StageDirections>#{escape_xml(stage)}</StageDirections>),
      ~s(          </DialogueFragment>)
    ] ++ List.flatten(response_xml)
  end

  defp build_articy_node(%{type: "condition"} = node, _speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    condition = Helpers.extract_condition(data["condition"])
    expr = transpile_or_empty(condition, :articy, :condition)

    [
      ~s(          <Condition Id="#{guid}" TechnicalName="cond_#{node.id}">),
      ~s(            <Expression>#{escape_xml(expr)}</Expression>),
      ~s(          </Condition>)
    ]
  end

  defp build_articy_node(%{type: "instruction"} = node, _speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    assignments = Helpers.extract_assignments(data)
    expr = transpile_or_empty(assignments, :articy, :instruction)

    [
      ~s(          <Instruction Id="#{guid}" TechnicalName="inst_#{node.id}">),
      ~s(            <Expression>#{escape_xml(expr)}</Expression>),
      ~s(          </Instruction>)
    ]
  end

  defp build_articy_node(%{type: "hub"} = node, _speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    label = data["label"] || ""

    [
      ~s(          <Hub Id="#{guid}" TechnicalName="hub_#{node.id}">),
      ~s(            <DisplayName>#{escape_xml(label)}</DisplayName>),
      ~s(          </Hub>)
    ]
  end

  defp build_articy_node(%{type: "jump"} = node, _speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    target = data["hub_id"] || data["target_flow_shortcut"] || ""

    [
      ~s(          <Jump Id="#{guid}" TechnicalName="jump_#{node.id}" Target="#{escape_xml(to_string(target))}"/>)
    ]
  end

  defp build_articy_node(%{type: type} = node, _speaker_map) when type in ["entry", "exit"] do
    guid = generate_guid("node:#{node.id}")

    [
      ~s(          <#{String.capitalize(type)} Id="#{guid}" TechnicalName="#{type}_#{node.id}"/>)
    ]
  end

  defp build_articy_node(%{type: "scene"} = node, _speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    location = data["location"] || data["slug_line"] || ""

    [
      ~s(          <LocationSettings Id="#{guid}" TechnicalName="scene_#{node.id}">),
      ~s(            <Location>#{escape_xml(location)}</Location>),
      ~s(          </LocationSettings>)
    ]
  end

  defp build_articy_node(%{type: "subflow"} = node, _speaker_map) do
    data = node.data || %{}
    guid = generate_guid("node:#{node.id}")
    flow_shortcut = data["flow_shortcut"] || ""

    [
      ~s(          <FlowFragment Id="#{guid}" TechnicalName="subflow_#{node.id}" Reference="#{escape_xml(flow_shortcut)}"/>)
    ]
  end

  defp build_articy_node(_node, _speaker_map), do: []

  # ---------------------------------------------------------------------------
  # Connections
  # ---------------------------------------------------------------------------

  defp build_connections(flow) do
    Enum.map(flow.connections, fn conn ->
      guid = generate_guid("conn:#{conn.id}")
      source_guid = generate_guid("node:#{conn.source_node_id}")
      target_guid = generate_guid("node:#{conn.target_node_id}")

      [
        ~s(          <Connection Id="#{guid}" Source="#{source_guid}" Target="#{target_guid}"/>)
      ]
    end)
  end

  # ---------------------------------------------------------------------------
  # GUID generation
  # ---------------------------------------------------------------------------

  @doc false
  def generate_guid(input) do
    # Deterministic: same input always produces same GUID
    # UUID v5 (SHA-1 based) with URL namespace
    hash =
      :crypto.hash(:sha, "#{@storyarn_namespace}:#{input}")
      |> Base.encode16(case: :upper)
      |> binary_part(0, 32)

    "0x#{hash}"
  end

  # ---------------------------------------------------------------------------
  # XML helpers
  # ---------------------------------------------------------------------------

  defp escape_xml(nil), do: ""

  defp escape_xml(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  # ---------------------------------------------------------------------------
  # Expression helpers
  # ---------------------------------------------------------------------------

  defp transpile_or_nil(nil, _engine, _type), do: nil

  defp transpile_or_nil(data, engine, :condition) do
    case ExpressionTranspiler.transpile_condition(data, engine) do
      {:ok, expr, _} when expr != "" -> expr
      _ -> nil
    end
  end

  defp transpile_or_empty(nil, _engine, _type), do: ""
  defp transpile_or_empty([], _engine, _type), do: ""

  defp transpile_or_empty(data, engine, :condition) do
    case ExpressionTranspiler.transpile_condition(data, engine) do
      {:ok, expr, _} -> expr
      _ -> ""
    end
  end

  defp transpile_or_empty(data, engine, :instruction) do
    case ExpressionTranspiler.transpile_instruction(data, engine) do
      {:ok, expr, _} -> expr
      _ -> ""
    end
  end
end
