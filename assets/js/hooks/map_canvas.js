/**
 * MapCanvas - Phoenix LiveView Hook for the interactive map editor.
 *
 * Thin orchestrator: delegates setup to map_canvas/setup.js,
 * complex logic split into handler factories in map_canvas/handlers/.
 */

import L from "leaflet";
import { toPercent } from "../map_canvas/coordinate_utils.js";
import { initMap, addGridPlaceholder } from "../map_canvas/setup.js";
import { createPinHandler } from "../map_canvas/handlers/pin_handler.js";
import { createZoneHandler } from "../map_canvas/handlers/zone_handler.js";
import { createConnectionHandler } from "../map_canvas/handlers/connection_handler.js";
import { createLayerHandler } from "../map_canvas/handlers/layer_handler.js";
import { createAnnotationHandler } from "../map_canvas/handlers/annotation_handler.js";
import { createContextMenu } from "../map_canvas/context_menu.js";
import { createMinimap } from "../map_canvas/minimap.js";
import { createRuler } from "../map_canvas/ruler.js";
import { exportPNG, exportSVG } from "../map_canvas/exporter.js";

export const MapCanvas = {
  mounted() {
    this.mapData = JSON.parse(this.el.dataset.map || "{}");
    this.i18n = JSON.parse(this.el.dataset.i18n || "{}");
    this.currentTool = this.mapData.can_edit ? "select" : "pan";
    this.editMode = this.mapData.can_edit !== false;
    this.pendingSheetForPin = false;
    this.initCanvas();
  },

  destroyed() {
    if (this._keydownHandler) {
      document.removeEventListener("keydown", this._keydownHandler);
    }
    if (this.ruler) this.ruler.destroy();
    if (this.minimap) this.minimap.destroy();
    if (this.contextMenu) this.contextMenu.destroy();
    if (this.layerHandler) this.layerHandler.destroy();
    if (this.connectionHandler) this.connectionHandler.destroy();
    if (this.annotationHandler) this.annotationHandler.destroy();
    if (this.pinHandler) this.pinHandler.destroy();
    if (this.zoneHandler) this.zoneHandler.destroy();

    if (this.leafletMap) {
      this.leafletMap.remove();
      this.leafletMap = null;
    }
  },

  initCanvas() {
    const { map, width, height } = initMap(this);
    this.leafletMap = map;
    this.canvasWidth = width;
    this.canvasHeight = height;

    // Initialize handlers (order matters: pins before connections, layers last)
    this.pinHandler = createPinHandler(this, this.i18n);
    this.pinHandler.init();

    this.zoneHandler = createZoneHandler(this, this.i18n);
    this.zoneHandler.init();

    this.connectionHandler = createConnectionHandler(this, this.i18n);
    this.connectionHandler.init();

    this.annotationHandler = createAnnotationHandler(this, this.i18n);
    this.annotationHandler.init();

    this.layerHandler = createLayerHandler(this);
    this.layerHandler.init();

    // Mini-map navigation
    this.minimap = createMinimap(this);
    this.minimap.init();

    // Ruler / distance measurement
    this.ruler = createRuler(this);

    // Context menu (shared across all handlers)
    this.contextMenu = createContextMenu(this);

    // Prevent browser context menu on canvas, show our own on empty canvas
    this.el.addEventListener("contextmenu", (e) => {
      e.preventDefault();
    });

    map.on("contextmenu", (e) => {
      if (!this.editMode) return;
      this.contextMenu.hide();

      const containerPoint = map.latLngToContainerPoint(e.latlng);
      const pos = { x: containerPoint.x, y: containerPoint.y };

      this.contextMenu.show(pos.x, pos.y, [
        {
          label: this.i18n.add_pin || "Add Pin Here",
          action: () => {
            const pct = this._toPercent(e.latlng);
            this.pushEvent("create_pin", { position_x: pct.x, position_y: pct.y });
          },
        },
        {
          label: this.i18n.add_annotation || "Add Annotation Here",
          action: () => {
            const pct = this._toPercent(e.latlng);
            this.pushEvent("create_annotation", { position_x: pct.x, position_y: pct.y });
          },
        },
      ]);
    });

    // Map click for deselection (when clicking empty canvas)
    map.on("click", (e) => {
      // Only deselect if in select or pan mode (other tools use clicks for creation)
      if (this.currentTool === "select" || this.currentTool === "pan") {
        this.pushEvent("deselect", {});
        this.pinHandler.deselectAll();
        this.zoneHandler.deselectAll();
        this.connectionHandler.deselectAll();
        this.annotationHandler.deselectAll();
      }
    });

    // Wire tool changes from server
    this.handleEvent("tool_changed", ({ tool }) => {
      const prevTool = this.currentTool;
      // Cancel any in-progress drawing when switching tools
      if (this.isZoneTool(prevTool) && !this.isZoneTool(tool)) {
        this.zoneHandler.cancelDrawing();
      }
      if (prevTool === "connector" && tool !== "connector") {
        this.connectionHandler.cancelDrawing();
        this.connectionHandler.clearAllPinStates();
      }
      if (prevTool === "ruler" && tool !== "ruler") {
        this.ruler.clear();
      }
      this.currentTool = tool;
      this.updateCursor();
    });

    // Wire sheet-for-pin state from server
    this.handleEvent("pending_sheet_changed", ({ active }) => {
      this.pendingSheetForPin = active;
    });

    // Wire edit mode changes from server
    this.handleEvent("edit_mode_changed", ({ edit_mode }) => {
      this.editMode = edit_mode;
      if (!edit_mode) {
        this.zoneHandler.cancelDrawing();
        this.connectionHandler.cancelDrawing();
        this.connectionHandler.clearAllPinStates();
        this.ruler.clear();
        this.currentTool = "pan";
      }
      // Toggle dragging on existing elements
      this.pinHandler.setEditMode(edit_mode);
      this.annotationHandler.setEditMode(edit_mode);
      this.updateCursor();
    });

    // Wire element selection from server
    this.handleEvent("element_selected", ({ type, id }) => {
      // Clear all selections first
      this.pinHandler.deselectAll();
      this.zoneHandler.deselectAll();
      this.connectionHandler.deselectAll();
      this.annotationHandler.deselectAll();

      if (type === "pin") {
        this.pinHandler.selectPin(id);
      } else if (type === "zone") {
        this.zoneHandler.selectZone(id);
      } else if (type === "connection") {
        this.connectionHandler.selectConnection(id);
      } else if (type === "annotation") {
        this.annotationHandler.selectAnnotation(id);
      }
    });

    this.handleEvent("element_deselected", () => {
      this.pinHandler.deselectAll();
      this.zoneHandler.deselectAll();
      this.connectionHandler.deselectAll();
      this.annotationHandler.deselectAll();
    });

    // Wire search highlight events
    this.handleEvent("highlight_elements", ({ elements }) => {
      // Dim all elements first
      this.pinHandler.setAllDimmed(true);
      this.zoneHandler.setAllDimmed(true);
      this.connectionHandler.setAllDimmed(true);
      this.annotationHandler.setAllDimmed(true);

      // Highlight matching elements
      for (const { type, id } of elements) {
        if (type === "pin") this.pinHandler.setDimmed(id, false);
        else if (type === "zone") this.zoneHandler.setDimmed(id, false);
        else if (type === "connection") this.connectionHandler.setDimmed(id, false);
        else if (type === "annotation") this.annotationHandler.setDimmed(id, false);
      }
    });

    this.handleEvent("clear_highlights", () => {
      this.pinHandler.clearDimming();
      this.zoneHandler.clearDimming();
      this.connectionHandler.clearDimming();
      this.annotationHandler.clearDimming();
    });

    this.handleEvent("focus_annotation_text", () => {
      // Delay to let the DOM update with the new panel
      requestAnimationFrame(() => {
        const el = document.getElementById("annotation-text-input");
        if (el) { el.focus(); el.select(); }
      });
    });

    this.handleEvent("focus_element", ({ type, id }) => {
      if (type === "pin") this.pinHandler.focusPin(id);
      else if (type === "zone") this.zoneHandler.focusZone(id);
      else if (type === "annotation") this.annotationHandler.focusAnnotation(id);
      // Connections span between pins — no single focus point
    });

    // Wire background image changes
    this.handleEvent("background_changed", ({ url }) => {
      // Remove existing background overlay or grid
      if (this.backgroundOverlay) {
        this.backgroundOverlay.remove();
        this.backgroundOverlay = null;
      }
      if (this.gridOverlay) {
        this.gridOverlay.remove();
        this.gridOverlay = null;
      }

      const bounds = [
        [0, 0],
        [-this.canvasHeight, this.canvasWidth],
      ];

      if (url) {
        this.backgroundOverlay = L.imageOverlay(url, bounds).addTo(this.leafletMap);
        // Send behind pins/zones/connections
        this.backgroundOverlay.bringToBack();
      } else {
        this.gridOverlay = addGridPlaceholder(this.leafletMap, this.canvasWidth, this.canvasHeight);
      }

      // Refresh minimap background
      if (this.minimap) this.minimap.refreshBackground();
    });

    // Wire map export
    this.handleEvent("export_map", ({ format }) => {
      const name = this.mapData.name || "map";
      const safeName = name.replace(/[^a-zA-Z0-9_-]/g, "_");
      if (format === "svg") {
        exportSVG(this, safeName);
      } else {
        exportPNG(this, safeName);
      }
    });

    // Keyboard shortcuts (Ctrl+Z undo, Ctrl+Shift+Z / Ctrl+Y redo)
    this._keydownHandler = (e) => {
      if (!this.editMode) return;
      const mod = e.metaKey || e.ctrlKey;
      if (!mod) return;

      if (e.key === "z" && !e.shiftKey) {
        e.preventDefault();
        this.pushEvent("undo", {});
      } else if ((e.key === "z" && e.shiftKey) || e.key === "y") {
        e.preventDefault();
        this.pushEvent("redo", {});
      }
    };
    document.addEventListener("keydown", this._keydownHandler);

    // Apply initial tool state (disable dragging for select mode)
    this.updateCursor();
  },

  /** Converts a Leaflet LatLng to percentage coordinates. */
  _toPercent(latLng) {
    return toPercent(latLng, this.canvasWidth, this.canvasHeight);
  },

  /** Returns true if the given tool is a zone creation tool. */
  isZoneTool(tool) {
    return ["rectangle", "triangle", "circle", "freeform"].includes(tool);
  },

  updateCursor() {
    const container = this.el.querySelector("#map-canvas-container");
    if (!container) return;

    const tool = this.currentTool;
    if (this.isZoneTool(tool) || tool === "pin" || tool === "connector" || tool === "annotation" || tool === "ruler") {
      container.style.cursor = "crosshair";
    } else if (tool === "pan") {
      container.style.cursor = "grab";
    } else {
      container.style.cursor = "";
    }

    // Figma-style: only pan mode allows map dragging
    if (this.leafletMap) {
      if (tool === "pan") {
        this.leafletMap.dragging.enable();
      } else {
        this.leafletMap.dragging.disable();
      }
    }
  },
};
