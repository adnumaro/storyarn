// Guard against missing localStorage/sessionStorage (Safari private browsing, old Safari)
// LiveView calls localStorage.removeItem in dropLocal() which crashes if storage is undefined
if (typeof window.localStorage === "undefined") {
  const noop = {
    getItem: () => null,
    setItem: () => {},
    removeItem: () => {},
    clear: () => {},
    key: () => null,
    length: 0,
  };
  Object.defineProperty(window, "localStorage", { value: noop });
}
if (typeof window.sessionStorage === "undefined") {
  const noop = {
    getItem: () => null,
    setItem: () => {},
    removeItem: () => {},
    clear: () => {},
    key: () => null,
    length: 0,
  };
  Object.defineProperty(window, "sessionStorage", { value: noop });
}

// Sentry browser error tracking (only initializes if DSN meta tag is present)
import * as Sentry from "@sentry/browser";

const sentryDsn = document.querySelector("meta[name='sentry-dsn']")?.getAttribute("content");
if (sentryDsn) {
  Sentry.init({
    dsn: sentryDsn,
    environment: window.location.hostname === "localhost" ? "development" : "production",
    // Don't send errors in development
    enabled: window.location.hostname !== "localhost",
    // Ignore common non-actionable errors
    ignoreErrors: [
      // Browser extensions and third-party scripts
      "ResizeObserver loop",
      "Non-Error promise rejection",
      // LiveView reconnection (expected behavior)
      "WebSocket connection",
      "transport was disconnected",
    ],
  });
}

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/storyarn";
import topbar from "topbar";

import { AssetUpload } from "./hooks/asset_upload";
import { AudioUpload } from "./hooks/audio_upload";
import { AvatarUpload } from "./hooks/avatar_upload";
import { BannerUpload } from "./hooks/banner_upload";
import { BlockKeyboard } from "./hooks/block_keyboard";
import { BlockMenu } from "./hooks/block_menu";
import { CanvasDropZone } from "./hooks/canvas_drop_zone";
import { CanvasToolbar } from "./hooks/canvas_toolbar";
import { ColorPicker } from "./hooks/color_picker";
// Custom hooks
import { ColumnSortable } from "./hooks/column_sortable";
import { ConditionBuilder } from "./hooks/condition_builder";
import { DebugPanelResize } from "./hooks/debug_panel_resize";
import { DebugVarsResize } from "./hooks/debug_vars_resize";
import { DetailsPreserveOpen } from "./hooks/details_preserve_open";
import { DialogueScreenplayEditor } from "./hooks/dialogue_screenplay_editor";
import { DocsScrollSpy } from "./hooks/docs_scroll_spy";
import { EditableBlockLabel } from "./hooks/editable_block_label";
import { EditableShortcut } from "./hooks/editable_shortcut";
import { EditableTitle } from "./hooks/editable_title";
import { ExplorationPlayer } from "./hooks/exploration_player";
import { ExpressionEditor } from "./hooks/expression_editor";
import { FlowCanvas } from "./hooks/flow_canvas";
import { FlowLoader } from "./hooks/flow_loader";
import { FormulaBinding } from "./hooks/formula_binding";
import { FormulaPreview } from "./hooks/formula_preview";
import { FountainImport } from "./hooks/fountain_import";
import { GallerySortable } from "./hooks/gallery_sortable";
import { GalleryUpload } from "./hooks/gallery_upload";
import { InstructionBuilder } from "./hooks/instruction_builder";
import { ReferenceSearch } from "./hooks/reference_search";
import { RightSidebar } from "./hooks/right_sidebar";
import { SceneCanvas } from "./hooks/scene_canvas";
import { ScreenplayEditor } from "./hooks/screenplay_editor";
import { ScrollCollapse } from "./hooks/scroll_collapse";
import { SearchableSelect } from "./hooks/searchable_select";
import { SettingsSidebar } from "./hooks/settings_sidebar";
import { SortableTree } from "./hooks/sortable_tree";
import { StoryPlayer } from "./hooks/story_player";
import { TableCellCheckbox } from "./hooks/table_cell_checkbox";
import { TableCellSelect } from "./hooks/table_cell_select";
import { TableColumnDropdown } from "./hooks/table_column_dropdown";
import { TableColumnResize } from "./hooks/table_column_resize";
import { TableRowMenu } from "./hooks/table_row_menu";
import { TableRowSortable } from "./hooks/table_row_sortable";
import { TiptapEditor } from "./hooks/tiptap_editor";
import { ToolbarPopover } from "./hooks/toolbar_popover";
import { TreeToggle } from "./hooks/tree";
import { TreePanel } from "./hooks/tree_panel";
import { TreeSearch } from "./hooks/tree_search";
import { TriStateCheckbox } from "./hooks/tri_state_checkbox";
import { TwoStateCheckbox } from "./hooks/two_state_checkbox";
import { UndoRedo } from "./hooks/undo_redo";

// Theme management (keyboard shortcuts, cross-tab sync)
import "./theme";

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    ...colocatedHooks,
    AssetUpload,
    AudioUpload,
    CanvasDropZone,
    AvatarUpload,
    BannerUpload,
    BlockKeyboard,
    BlockMenu,
    ColumnSortable,
    EditableBlockLabel,
    EditableShortcut,
    EditableTitle,
    SortableTree,
    TreePanel,
    TreeToggle,
    TreeSearch,
    TiptapEditor,
    TriStateCheckbox,
    TwoStateCheckbox,
    FlowCanvas,
    FlowLoader,
    GallerySortable,
    GalleryUpload,
    InstructionBuilder,
    ColorPicker,
    ConditionBuilder,
    DebugPanelResize,
    DebugVarsResize,
    DetailsPreserveOpen,
    DocsScrollSpy,
    FountainImport,
    SceneCanvas,
    CanvasToolbar,
    ReferenceSearch,
    RightSidebar,
    ScrollCollapse,
    SearchableSelect,
    SettingsSidebar,
    DialogueScreenplayEditor,
    ScreenplayEditor,
    StoryPlayer,
    ExplorationPlayer,
    ExpressionEditor,
    FormulaBinding,
    FormulaPreview,
    TableCellCheckbox,
    TableCellSelect,
    TableColumnDropdown,
    TableColumnResize,
    TableRowMenu,
    TableRowSortable,
    ToolbarPopover,
    UndoRedo,
  },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());
window.addEventListener("phx:sheet-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:sheet-loading-stop", (_info) => topbar.hide());

// Handle native dialog methods via custom events (used by show_modal/hide_modal in core_components)
window.addEventListener("phx:show-modal", (event) => {
  if (event.target instanceof HTMLDialogElement) {
    event.target.showModal();
  }
});

window.addEventListener("phx:hide-modal", (event) => {
  if (event.target instanceof HTMLDialogElement) {
    event.target.close();
    // Workaround: re-open and re-close to force top layer cleanup (Chrome bug)
    requestAnimationFrame(() => {
      if (!event.target.open && event.target.isConnected) {
        try {
          event.target.showModal();
          event.target.close();
        } catch (_) {
          /* ignore */
        }
      }
    });
  }
});

// Safety net: force-clean top layer for dialogs that were opened with showModal().
// Chrome bug: closing a showModal() dialog can leave ::backdrop stuck in the top layer,
// blocking all page interaction. The showModal()+close() cycle forces proper cleanup.
function forceCleanDialogs() {
  document.querySelectorAll("dialog").forEach((d) => {
    if (!d.open) {
      try {
        d.showModal();
        d.close();
      } catch (_) {
        /* ignore if dialog is not connected to DOM */
      }
    }
  });
}
window.addEventListener("phx:page-loading-start", forceCleanDialogs);
window.addEventListener("phx:page-loading-stop", forceCleanDialogs);

// Handle panel open/close from server push_event
// Server does: push_event(socket, "panel-open", %{to: "#my-panel"})
window.addEventListener("phx:panel-open", (event) => {
  const el = document.querySelector(event.detail.to);
  if (el) el.dispatchEvent(new Event("panel:open"));
});

window.addEventListener("phx:panel-close", (event) => {
  const el = document.querySelector(event.detail.to);
  if (el) el.dispatchEvent(new Event("panel:close"));
});

// Handle copy to clipboard via click events
window.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-text]");
  if (button) {
    const text = button.dataset.copyText || "";
    if (text) {
      try {
        await navigator.clipboard.writeText(text);
        // Visual feedback: briefly change icon
        const icon = button.querySelector("svg");
        if (icon) {
          icon.classList.add("text-success");
          setTimeout(() => icon.classList.remove("text-success"), 1000);
        }
      } catch (err) {
        // biome-ignore lint/suspicious/noConsole: intentional error logging
        console.error("Failed to copy to clipboard:", err);
      }
    }
  }
});

// connect if there are any LiveViews on the sheet
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs();

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown;
    window.addEventListener("keydown", (e) => (keyDown = e.key));
    window.addEventListener("keyup", (_e) => (keyDown = null));
    window.addEventListener(
      "click",
      (e) => {
        if (keyDown === "c") {
          e.preventDefault();
          e.stopImmediatePropagation();
          reloader.openEditorAtCaller(e.target);
        } else if (keyDown === "d") {
          e.preventDefault();
          e.stopImmediatePropagation();
          reloader.openEditorAtDef(e.target);
        }
      },
      true,
    );

    window.liveReloader = reloader;
  });
}
