import { LitPlugin, Presets as LitPresets } from "@retejs/lit-plugin";
import { LitElement, html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ArrowRight, GitBranch, GitMerge, MessageSquare, Zap, createElement } from "lucide";
import { ClassicPreset, NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";

// Node type configurations
const NODE_CONFIGS = {
  dialogue: {
    label: "Dialogue",
    color: "#3b82f6",
    colorClass: "bg-blue-500",
    borderClass: "border-blue-500/25",
    icon: MessageSquare,
    inputs: ["input"],
    outputs: ["output"],
  },
  hub: {
    label: "Hub",
    color: "#8b5cf6",
    colorClass: "bg-violet-500",
    borderClass: "border-violet-500/25",
    icon: GitMerge,
    inputs: ["input"],
    outputs: ["out1", "out2", "out3", "out4"],
  },
  condition: {
    label: "Condition",
    color: "#f59e0b",
    colorClass: "bg-amber-500",
    borderClass: "border-amber-500/25",
    icon: GitBranch,
    inputs: ["input"],
    outputs: ["true", "false"],
  },
  instruction: {
    label: "Instruction",
    color: "#10b981",
    colorClass: "bg-emerald-500",
    borderClass: "border-emerald-500/25",
    icon: Zap,
    inputs: ["input"],
    outputs: ["output"],
  },
  jump: {
    label: "Jump",
    color: "#ef4444",
    colorClass: "bg-red-500",
    borderClass: "border-red-500/25",
    icon: ArrowRight,
    inputs: ["input"],
    outputs: [],
  },
};

// Custom styled node component (Light DOM for Tailwind support)
class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
    };
  }

  // Use Light DOM instead of Shadow DOM for Tailwind support
  createRenderRoot() {
    return this;
  }

  render() {
    const node = this.data;
    const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;
    const nodeData = node.nodeData || {};

    // Get preview text based on node type
    let preview = "";
    if (node.nodeType === "dialogue") {
      preview = nodeData.speaker || nodeData.text || "";
    } else if (node.nodeType === "hub") {
      preview = nodeData.label || "";
    } else if (node.nodeType === "condition") {
      preview = nodeData.expression || "";
    } else if (node.nodeType === "instruction") {
      preview = nodeData.action || "";
    } else if (node.nodeType === "jump") {
      preview = nodeData.target_flow || "";
    }

    // Create lucide icon element and get SVG string
    const iconElement = createElement(config.icon, { class: "size-4" });
    const iconSvg = iconElement.outerHTML;

    const selectedClass = node.selected
      ? "ring-2 ring-primary ring-offset-2 ring-offset-base-100"
      : "";

    return html`
      <div class="flow-node bg-base-100 rounded-lg min-w-[180px] shadow-md border-[1.5px] ${config.borderClass} ${selectedClass} transition-shadow hover:shadow-lg">
        <div class="flow-node-header ${config.colorClass} px-3 py-2 rounded-t-md flex items-center gap-2 text-white font-medium text-sm">
          <span class="flex items-center">${unsafeSVG(iconSvg)}</span>
          <span>${config.label}</span>
        </div>
        <div class="flow-node-content px-3 py-2">
          <div class="flex flex-col gap-1">
            ${Object.keys(node.inputs || {}).map(
              (key) => html`
                <div class="flex items-center gap-2 text-xs text-base-content/70">
                  <slot name="input-socket-${key}"></slot>
                  <span>${key}</span>
                </div>
              `,
            )}
            ${Object.keys(node.outputs || {}).map(
              (key) => html`
                <div class="flex items-center gap-2 text-xs text-base-content/70 justify-end">
                  <span>${key}</span>
                  <slot name="output-socket-${key}"></slot>
                </div>
              `,
            )}
          </div>
        </div>
        ${
          preview
            ? html`<div class="text-xs text-base-content/60 px-3 pb-2 max-w-[160px] truncate">${preview}</div>`
            : ""
        }
      </div>
    `;
  }
}

customElements.define("storyarn-node", StoryarnNode);

// Custom node class
class FlowNode extends ClassicPreset.Node {
  constructor(type, id, data = {}) {
    const config = NODE_CONFIGS[type] || NODE_CONFIGS.dialogue;
    super(config.label);

    this.nodeType = type;
    this.nodeId = id;
    this.nodeData = data;

    // Add inputs
    for (const inputName of config.inputs) {
      this.addInput(inputName, new ClassicPreset.Input(new ClassicPreset.Socket("flow")));
    }

    // Add outputs
    for (const outputName of config.outputs) {
      this.addOutput(outputName, new ClassicPreset.Output(new ClassicPreset.Socket("flow")));
    }
  }
}

export const FlowCanvas = {
  mounted() {
    this.initEditor();
  },

  async initEditor() {
    const container = this.el;
    const flowData = JSON.parse(container.dataset.flow || "{}");

    // Create the editor
    this.editor = new NodeEditor();
    this.area = new AreaPlugin(container);
    this.connection = new ConnectionPlugin();
    this.minimap = new MinimapPlugin();

    // Create render plugin with Lit
    this.render = new LitPlugin();

    // Configure connection plugin
    this.connection.addPreset(ConnectionPresets.classic.setup());

    // Configure Lit render plugin with custom node component
    this.render.addPreset(
      LitPresets.classic.setup({
        customize: {
          node(context) {
            return ({ emit }) => html`
              <storyarn-node
                .data=${context.payload}
                .emit=${emit}
              ></storyarn-node>
            `;
          },
        },
      }),
    );

    // Register plugins
    this.editor.use(this.area);
    this.area.use(this.connection);
    this.area.use(this.render);
    this.area.use(this.minimap);

    // Track nodes by database ID
    this.nodeMap = new Map();
    this.debounceTimers = {};
    // Flag to prevent sending events when adding from server
    this.isLoadingFromServer = false;

    // Load initial flow data
    if (flowData.nodes) {
      await this.loadFlow(flowData);
    }

    // Set up event handlers
    this.setupEventHandlers();

    // Enable zoom and pan
    AreaExtensions.selectableNodes(this.area, AreaExtensions.selector(), {
      accumulating: AreaExtensions.accumulateOnCtrl(),
    });

    // Fit view to content if there are nodes
    if (flowData.nodes && flowData.nodes.length > 0) {
      setTimeout(async () => {
        await AreaExtensions.zoomAt(this.area, this.editor.getNodes());
      }, 100);
    }
  },

  async loadFlow(flowData) {
    this.isLoadingFromServer = true;
    try {
      // Create nodes
      for (const nodeData of flowData.nodes || []) {
        await this.addNodeToEditor(nodeData);
      }

      // Create connections
      for (const connData of flowData.connections || []) {
        await this.addConnectionToEditor(connData);
      }
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  async addNodeToEditor(nodeData) {
    const node = new FlowNode(nodeData.type, nodeData.id, nodeData.data);
    node.id = `node-${nodeData.id}`;

    await this.editor.addNode(node);
    await this.area.translate(node.id, {
      x: nodeData.position?.x || 0,
      y: nodeData.position?.y || 0,
    });

    this.nodeMap.set(nodeData.id, node);
    return node;
  },

  async addConnectionToEditor(connData) {
    const sourceNode = this.nodeMap.get(connData.source_node_id);
    const targetNode = this.nodeMap.get(connData.target_node_id);

    if (!sourceNode || !targetNode) return;

    const connection = new ClassicPreset.Connection(
      sourceNode,
      connData.source_pin,
      targetNode,
      connData.target_pin,
    );
    connection.id = `conn-${connData.id}`;

    await this.editor.addConnection(connection);
    return connection;
  },

  setupEventHandlers() {
    // Node position changes (drag)
    this.area.addPipe((context) => {
      if (context.type === "nodetranslated") {
        const node = this.editor.getNode(context.data.id);
        if (node?.nodeId) {
          this.debounceNodeMoved(node.nodeId, context.data.position);
        }
      }
      return context;
    });

    // Node selection
    this.area.addPipe((context) => {
      if (context.type === "nodepicked") {
        const node = this.editor.getNode(context.data.id);
        if (node?.nodeId) {
          this.pushEvent("node_selected", { id: node.nodeId });
        }
      }
      return context;
    });

    // Connection created
    this.editor.addPipe((context) => {
      if (context.type === "connectioncreate" && !this.isLoadingFromServer) {
        const conn = context.data;
        const sourceNode = this.editor.getNode(conn.source);
        const targetNode = this.editor.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          this.pushEvent("connection_created", {
            source_node_id: sourceNode.nodeId,
            source_pin: conn.sourceOutput,
            target_node_id: targetNode.nodeId,
            target_pin: conn.targetInput,
          });
        }
      }
      return context;
    });

    // Connection deleted
    this.editor.addPipe((context) => {
      if (context.type === "connectionremove" && !this.isLoadingFromServer) {
        const conn = context.data;
        const sourceNode = this.editor.getNode(conn.source);
        const targetNode = this.editor.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          this.pushEvent("connection_deleted", {
            source_node_id: sourceNode.nodeId,
            target_node_id: targetNode.nodeId,
          });
        }
      }
      return context;
    });

    // Handle server events
    this.handleEvent("flow_updated", (data) => this.handleFlowUpdated(data));
    this.handleEvent("node_added", (data) => this.handleNodeAdded(data));
    this.handleEvent("node_removed", (data) => this.handleNodeRemoved(data));
    this.handleEvent("connection_added", (data) => this.handleConnectionAdded(data));
    this.handleEvent("connection_removed", (data) => this.handleConnectionRemoved(data));
  },

  debounceNodeMoved(nodeId, position) {
    if (this.debounceTimers[nodeId]) {
      clearTimeout(this.debounceTimers[nodeId]);
    }

    this.debounceTimers[nodeId] = setTimeout(() => {
      this.pushEvent("node_moved", {
        id: nodeId,
        position_x: position.x,
        position_y: position.y,
      });
      delete this.debounceTimers[nodeId];
    }, 300);
  },

  async handleFlowUpdated(data) {
    // Clear existing nodes and connections
    for (const conn of this.editor.getConnections()) {
      await this.editor.removeConnection(conn.id);
    }
    for (const node of this.editor.getNodes()) {
      await this.editor.removeNode(node.id);
    }
    this.nodeMap.clear();

    // Reload flow
    await this.loadFlow(data);
  },

  async handleNodeAdded(data) {
    await this.addNodeToEditor(data);
  },

  async handleNodeRemoved(data) {
    const node = this.nodeMap.get(data.id);
    if (node) {
      await this.editor.removeNode(node.id);
      this.nodeMap.delete(data.id);
    }
  },

  async handleConnectionAdded(data) {
    this.isLoadingFromServer = true;
    try {
      await this.addConnectionToEditor(data);
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  async handleConnectionRemoved(data) {
    this.isLoadingFromServer = true;
    try {
      const connections = this.editor.getConnections();
      for (const conn of connections) {
        const sourceNode = this.editor.getNode(conn.source);
        const targetNode = this.editor.getNode(conn.target);

        if (
          sourceNode?.nodeId === data.source_node_id &&
          targetNode?.nodeId === data.target_node_id
        ) {
          await this.editor.removeConnection(conn.id);
          break;
        }
      }
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  destroyed() {
    // Clear all debounce timers
    for (const timer of Object.values(this.debounceTimers)) {
      clearTimeout(timer);
    }

    // Destroy plugins
    if (this.minimap) {
      this.minimap.destroy();
    }
    if (this.area) {
      this.area.destroy();
    }
  },
};

// Inject minimap styles (Rete.js specific classes)
const minimapStyles = document.createElement("style");
minimapStyles.textContent = `
  .rete-minimap {
    position: absolute;
    right: 16px;
    bottom: 16px;
    width: 200px;
    height: 150px;
    background: oklch(var(--b1));
    border: 1px solid oklch(var(--bc) / 0.2);
    border-radius: 8px;
    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);
    overflow: hidden;
    z-index: 10;
  }
  .rete-minimap .mini-node {
    border-radius: 2px;
  }
  .rete-minimap .mini-viewport {
    border: 2px solid oklch(var(--p));
    background: oklch(var(--p) / 0.1);
    border-radius: 4px;
  }
`;
document.head.appendChild(minimapStyles);
