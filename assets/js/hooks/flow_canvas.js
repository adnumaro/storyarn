import { LitPlugin, Presets as LitPresets } from "@retejs/lit-plugin";
import { LitElement, css, html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ArrowRight, GitBranch, GitMerge, MessageSquare, Zap, createElement } from "lucide";
import { ClassicPreset, NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";

// Helper to create Lucide icon SVG string
function createIconSvg(icon) {
  const el = createElement(icon, {
    width: 16,
    height: 16,
    stroke: "currentColor",
    "stroke-width": 2,
  });
  return el.outerHTML;
}

// Node type configurations
const NODE_CONFIGS = {
  dialogue: {
    label: "Dialogue",
    color: "#3b82f6",
    icon: createIconSvg(MessageSquare),
    inputs: ["input"],
    outputs: ["output"],
  },
  hub: {
    label: "Hub",
    color: "#8b5cf6",
    icon: createIconSvg(GitMerge),
    inputs: ["input"],
    outputs: ["out1", "out2", "out3", "out4"],
  },
  condition: {
    label: "Condition",
    color: "#f59e0b",
    icon: createIconSvg(GitBranch),
    inputs: ["input"],
    outputs: ["true", "false"],
  },
  instruction: {
    label: "Instruction",
    color: "#10b981",
    icon: createIconSvg(Zap),
    inputs: ["input"],
    outputs: ["output"],
  },
  jump: {
    label: "Jump",
    color: "#ef4444",
    icon: createIconSvg(ArrowRight),
    inputs: ["input"],
    outputs: [],
  },
};

// Custom styled node component (Shadow DOM for socket slots to work)
class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
    };
  }

  // Shadow DOM styles using daisyUI CSS variables (they pierce Shadow DOM)
  static styles = css`
    :host {
      display: block;
    }

    .node {
      background: oklch(var(--b1, 0.2 0 0));
      border-radius: 8px;
      min-width: 180px;
      box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
      border: 1.5px solid var(--node-border-color, transparent);
      transition: box-shadow 0.2s;
    }

    .node:hover {
      box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
    }

    .node.selected {
      box-shadow: 0 0 0 3px oklch(var(--p, 0.6 0.2 250) / 0.5), 0 4px 6px -1px rgb(0 0 0 / 0.1);
    }

    .header {
      padding: 8px 12px;
      border-radius: 6px 6px 0 0;
      display: flex;
      align-items: center;
      gap: 8px;
      color: white;
      font-weight: 500;
      font-size: 13px;
    }

    .icon {
      display: flex;
      align-items: center;
    }

    .content {
      padding: 8px 0;
    }

    .socket-row {
      display: flex;
      align-items: center;
      padding: 4px 0;
      font-size: 11px;
      color: oklch(var(--bc, 0.8 0 0) / 0.7);
    }

    .socket-row.input {
      justify-content: flex-start;
      padding-left: 0;
    }

    .socket-row.output {
      justify-content: flex-end;
      padding-right: 0;
    }

    .socket-row .label {
      padding: 0 8px;
    }

    .input-socket {
      margin-left: -10px;
    }

    .output-socket {
      margin-right: -10px;
    }

    .node-data {
      font-size: 11px;
      color: oklch(var(--bc, 0.8 0 0) / 0.6);
      padding: 4px 12px 8px;
      max-width: 160px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  `;

  render() {
    const node = this.data;
    if (!node) return html``;

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

    // Calculate border color with opacity
    const borderColor = `${config.color}40`;

    return html`
      <div
        class="node ${node.selected ? "selected" : ""}"
        style="--node-border-color: ${borderColor}"
      >
        <div class="header" style="background-color: ${config.color}">
          <span class="icon">${unsafeSVG(config.icon)}</span>
          <span>${config.label}</span>
        </div>
        <div class="content">
          ${Object.entries(node.inputs || {}).map(
            ([key, input]) => html`
              <div class="socket-row input">
                <rete-ref
                  class="input-socket"
                  .data=${{
                    type: "socket",
                    side: "input",
                    key,
                    nodeId: node.id,
                    payload: input.socket,
                  }}
                  .emit=${this.emit}
                ></rete-ref>
                <span class="label">${key}</span>
              </div>
            `,
          )}
          ${Object.entries(node.outputs || {}).map(
            ([key, output]) => html`
              <div class="socket-row output">
                <span class="label">${key}</span>
                <rete-ref
                  class="output-socket"
                  .data=${{
                    type: "socket",
                    side: "output",
                    key,
                    nodeId: node.id,
                    payload: output.socket,
                  }}
                  .emit=${this.emit}
                ></rete-ref>
              </div>
            `,
          )}
        </div>
        ${preview ? html`<div class="node-data">${preview}</div>` : ""}
      </div>
    `;
  }
}

customElements.define("storyarn-node", StoryarnNode);

// Custom socket component - smaller and subtle
class StoryarnSocket extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
    };
  }

  static styles = css`
    :host {
      display: inline-block;
    }

    .socket {
      width: 10px;
      height: 10px;
      background: oklch(var(--bc, 0.7 0 0) / 0.25);
      border: 2px solid oklch(var(--bc, 0.7 0 0) / 0.5);
      border-radius: 50%;
      cursor: crosshair;
      transition: all 0.15s ease;
    }

    .socket:hover {
      background: oklch(var(--p, 0.6 0.2 250));
      border-color: oklch(var(--p, 0.6 0.2 250));
      transform: scale(1.3);
    }
  `;

  render() {
    return html`<div class="socket" title="${this.data?.name || ""}"></div>`;
  }
}

customElements.define("storyarn-socket", StoryarnSocket);

// Custom connection component - thinner lines with label support
class StoryarnConnection extends LitElement {
  static get properties() {
    return {
      path: { type: String },
      start: { type: Object },
      end: { type: Object },
      data: { type: Object },
      selected: { type: Boolean },
    };
  }

  static styles = css`
    :host {
      display: contents;
    }

    svg {
      overflow: visible;
      position: absolute;
      pointer-events: none;
      width: 9999px;
      height: 9999px;
    }

    path {
      fill: none;
      stroke: oklch(var(--bc, 0.7 0 0) / 0.4);
      stroke-width: 2px;
      pointer-events: auto;
      transition: stroke 0.15s ease, stroke-width 0.15s ease;
      cursor: pointer;
    }

    path:hover,
    path.selected {
      stroke: oklch(var(--p, 0.6 0.2 250));
      stroke-width: 3px;
    }

    .label-group {
      pointer-events: auto;
      cursor: pointer;
    }

    .label-bg {
      fill: oklch(var(--b1, 0.2 0 0));
      stroke: oklch(var(--bc, 0.7 0 0) / 0.3);
      stroke-width: 1px;
      rx: 3;
      ry: 3;
    }

    .label-text {
      fill: oklch(var(--bc, 0.8 0 0));
      font-size: 10px;
      font-family: system-ui, sans-serif;
      dominant-baseline: middle;
      text-anchor: middle;
    }
  `;

  // Calculate midpoint of bezier curve path
  getMidpoint() {
    if (!this.path) return null;

    // Parse the path to get control points
    // Path format: M startX,startY C cp1X,cp1Y cp2X,cp2Y endX,endY
    const pathMatch = this.path.match(
      /M\s*([\d.-]+)[,\s]*([\d.-]+)\s*C\s*([\d.-]+)[,\s]*([\d.-]+)\s*([\d.-]+)[,\s]*([\d.-]+)\s*([\d.-]+)[,\s]*([\d.-]+)/,
    );

    if (!pathMatch) return null;

    const [, x0, y0, x1, y1, x2, y2, x3, y3] = pathMatch.map(Number);

    // Calculate midpoint of cubic bezier at t=0.5
    const t = 0.5;
    const mt = 1 - t;
    const mx = mt ** 3 * x0 + 3 * mt ** 2 * t * x1 + 3 * mt * t ** 2 * x2 + t ** 3 * x3;
    const my = mt ** 3 * y0 + 3 * mt ** 2 * t * y1 + 3 * mt * t ** 2 * y2 + t ** 3 * y3;

    return { x: mx, y: my };
  }

  render() {
    const label = this.data?.label;
    const midpoint = label ? this.getMidpoint() : null;
    const labelWidth = label ? Math.min(label.length * 6 + 10, 80) : 0;

    return html`
      <svg data-testid="connection">
        <path
          d="${this.path}"
          class="${this.selected ? "selected" : ""}"
          @dblclick=${this.handleDoubleClick}
        ></path>
        ${
          midpoint && label
            ? html`
              <g
                class="label-group"
                transform="translate(${midpoint.x}, ${midpoint.y})"
                @dblclick=${this.handleDoubleClick}
              >
                <rect
                  class="label-bg"
                  x="${-labelWidth / 2}"
                  y="-9"
                  width="${labelWidth}"
                  height="18"
                ></rect>
                <text class="label-text">${label}</text>
              </g>
            `
            : ""
        }
      </svg>
    `;
  }

  handleDoubleClick(e) {
    e.stopPropagation();
    if (this.data?.id) {
      this.dispatchEvent(
        new CustomEvent("connection-dblclick", {
          detail: { connectionId: this.data.id },
          bubbles: true,
          composed: true,
        }),
      );
    }
  }
}

customElements.define("storyarn-connection", StoryarnConnection);

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

    // Track connection data for labels
    this.connectionDataMap = new Map();

    // Configure Lit render plugin with custom components
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
          socket(context) {
            return () => html`
              <storyarn-socket .data=${context.payload}></storyarn-socket>
            `;
          },
          connection: (context) => {
            // Store connection data for lookup
            const conn = context.payload;
            return ({ path }) => {
              const connData = this.connectionDataMap.get(conn.id);
              return html`
                <storyarn-connection
                  .path=${path}
                  .data=${connData}
                  .selected=${this.selectedConnectionId === connData?.id}
                ></storyarn-connection>
              `;
            };
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

    // Store connection data for label rendering
    this.connectionDataMap.set(connection.id, {
      id: connData.id,
      label: connData.label,
      condition: connData.condition,
    });

    await this.editor.addConnection(connection);
    return connection;
  },

  setupEventHandlers() {
    // Track selected node/connection for keyboard shortcuts
    this.selectedNodeId = null;
    this.selectedConnectionId = null;

    // Listen for connection double-clicks (bubbles from Shadow DOM)
    this.el.addEventListener("connection-dblclick", (e) => {
      const { connectionId } = e.detail;
      if (connectionId) {
        this.selectedConnectionId = connectionId;
        this.pushEvent("connection_selected", { id: connectionId });
      }
    });

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
          this.selectedNodeId = node.nodeId;
          this.pushEvent("node_selected", { id: node.nodeId });
        }
      }
      return context;
    });

    // Keyboard shortcuts
    this.keyboardHandler = (e) => this.handleKeyboard(e);
    document.addEventListener("keydown", this.keyboardHandler);

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
    this.handleEvent("connection_updated", (data) => this.handleConnectionUpdated(data));
    this.handleEvent("deselect_connection", () => {
      this.selectedConnectionId = null;
    });
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
    this.connectionDataMap.clear();

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

      // Clear selection if the removed node was selected
      if (this.selectedNodeId === data.id) {
        this.selectedNodeId = null;
      }
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
          this.connectionDataMap.delete(conn.id);
          await this.editor.removeConnection(conn.id);
          break;
        }
      }
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  handleConnectionUpdated(data) {
    const connId = `conn-${data.id}`;
    // Update the connection data map
    this.connectionDataMap.set(connId, {
      id: data.id,
      label: data.label,
      condition: data.condition,
    });

    // Force re-render of the connection by triggering area update
    const conn = this.editor.getConnections().find((c) => c.id === connId);
    if (conn) {
      this.area.update("connection", conn.id);
    }
  },

  handleKeyboard(e) {
    // Ignore if focus is in an input field
    if (
      e.target.tagName === "INPUT" ||
      e.target.tagName === "TEXTAREA" ||
      e.target.isContentEditable
    ) {
      return;
    }

    // Delete/Backspace - delete selected node
    if ((e.key === "Delete" || e.key === "Backspace") && this.selectedNodeId) {
      e.preventDefault();
      this.pushEvent("delete_node", { id: this.selectedNodeId });
      this.selectedNodeId = null;
      return;
    }

    // Ctrl+D / Cmd+D - duplicate selected node
    if ((e.ctrlKey || e.metaKey) && e.key === "d" && this.selectedNodeId) {
      e.preventDefault();
      this.pushEvent("duplicate_node", { id: this.selectedNodeId });
      return;
    }

    // Escape - deselect node
    if (e.key === "Escape" && this.selectedNodeId) {
      e.preventDefault();
      this.pushEvent("deselect_node", {});
      this.selectedNodeId = null;
      return;
    }
  },

  destroyed() {
    // Remove keyboard listener
    if (this.keyboardHandler) {
      document.removeEventListener("keydown", this.keyboardHandler);
    }

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

// Inject global styles for canvas and minimap
const reteStyles = document.createElement("style");
reteStyles.textContent = `
  /* Canvas background with subtle dot grid */
  #flow-canvas {
    background-color: oklch(var(--b2, 0.2 0 0));
    background-image:
      radial-gradient(circle at center, oklch(var(--bc, 0.8 0 0) / 0.08) 1.5px, transparent 1.5px);
    background-size: 24px 24px;
  }

  /* Minimap styling */
  .rete-minimap {
    position: absolute;
    right: 16px;
    bottom: 16px;
    width: 180px;
    height: 120px;
    background: oklch(var(--b1, 0.25 0 0) / 0.9);
    border: 1px solid oklch(var(--bc, 0.8 0 0) / 0.2);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgb(0 0 0 / 0.15);
    overflow: hidden;
    z-index: 10;
    backdrop-filter: blur(8px);
  }

  .rete-minimap .mini-node {
    border-radius: 2px;
    opacity: 0.8;
  }

  .rete-minimap .mini-viewport {
    border: 2px solid oklch(var(--p, 0.6 0.2 250));
    background: oklch(var(--p, 0.6 0.2 250) / 0.1);
    border-radius: 3px;
  }
`;
document.head.appendChild(reteStyles);
