/**
 * Expression tab switcher for screenplay TipTap NodeViews.
 *
 * Adds Builder | Code tabs to condition/instruction atom nodes.
 * "Builder" shows the visual builder; "Code" shows a CodeMirror editor.
 * Switching tabs serializes/parses data bidirectionally.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.dom - The NodeView outer DOM element
 * @param {HTMLElement} opts.builderContainer - The visual builder container
 * @param {"condition"|"instruction"} opts.mode - Editor mode
 * @param {Function} opts.getData - Returns current structured data from builder
 * @param {Function} opts.pushEvent - LiveView pushEvent function
 * @param {string} opts.eventName - Event name for pushEvent
 * @param {Object} opts.context - Context params (element-id, etc.)
 * @param {Array} opts.variables - Project variables for autocomplete
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @returns {{ destroy: Function }}
 */

import { parseAssignments, parseCondition } from "../../expression_editor/parser.js";
import { serializeAssignments, serializeCondition } from "../../expression_editor/serializer.js";
import { createExpressionEditor } from "../../expression_editor/setup.js";

export function addExpressionTabs(opts) {
  const {
    dom,
    builderContainer,
    mode,
    getData,
    pushEvent,
    eventName,
    context,
    variables = [],
    canEdit = false,
  } = opts;

  let activeTab = "builder";
  let codeEditor = null;

  // Create tab bar
  const tabBar = document.createElement("div");
  tabBar.className = "flex items-center gap-1 mb-2 mt-1";

  const builderBtn = document.createElement("button");
  builderBtn.type = "button";
  builderBtn.textContent = "Builder";
  builderBtn.className = "sp-expr-tab sp-expr-tab-active";

  const codeBtn = document.createElement("button");
  codeBtn.type = "button";
  codeBtn.textContent = "Code";
  codeBtn.className = "sp-expr-tab";

  tabBar.appendChild(builderBtn);
  tabBar.appendChild(codeBtn);

  // Insert tab bar before builder container
  dom.insertBefore(tabBar, builderContainer);

  // Code editor container (hidden initially)
  const codeContainer = document.createElement("div");
  codeContainer.className = "sp-expr-code-container hidden";
  codeContainer.style.minHeight = "60px";
  dom.insertBefore(codeContainer, builderContainer.nextSibling);

  function switchTab(tab) {
    if (tab === activeTab) return;
    activeTab = tab;

    builderBtn.classList.toggle("sp-expr-tab-active", tab === "builder");
    codeBtn.classList.toggle("sp-expr-tab-active", tab === "code");

    if (tab === "code") {
      builderContainer.classList.add("hidden");
      codeContainer.classList.remove("hidden");
      showCodeEditor();
    } else {
      codeContainer.classList.add("hidden");
      builderContainer.classList.remove("hidden");
      destroyCodeEditor();
    }
  }

  function showCodeEditor() {
    destroyCodeEditor();

    const data = getData();
    const text = mode === "condition" ? serializeCondition(data) : serializeAssignments(data);

    const cmMode = mode === "condition" ? "expression" : "assignments";

    codeEditor = createExpressionEditor({
      container: codeContainer,
      content: text,
      mode: cmMode,
      editable: canEdit,
      placeholderText: mode === "condition" ? "mc.jaime.health > 50" : "mc.jaime.health = 50",
      variables,
      onChange: (newText) => {
        if (!canEdit) return;
        pushParsedData(newText);
      },
    });
  }

  function pushParsedData(text) {
    if (mode === "condition") {
      const result = parseCondition(text);
      if (result.errors.length > 0) return;
      const condition = result.condition || { logic: "all", rules: [] };
      const payload = { condition, ...context };
      pushEvent(eventName, payload);
    } else {
      const result = parseAssignments(text);
      if (result.errors.length > 0) return;
      const assignments = result.assignments || [];
      pushEvent(eventName, { assignments, ...context });
    }
  }

  function destroyCodeEditor() {
    if (codeEditor) {
      codeEditor.destroy();
      codeEditor = null;
      codeContainer.innerHTML = "";
    }
  }

  builderBtn.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    switchTab("builder");
  });

  codeBtn.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    switchTab("code");
  });

  return {
    destroy: () => {
      destroyCodeEditor();
      tabBar.remove();
      codeContainer.remove();
    },
  };
}
