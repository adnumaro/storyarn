/**
 * Response builder — renders the full choice list UI for response blocks.
 *
 * Each choice has: text input, condition/instruction toggles with nested builders,
 * linked page controls (create, navigate, unlink).
 */

import { createElement, FileText, Unlink, FilePlus, GitBranch, Zap, X, Plus } from "lucide";
import { createConditionBuilder } from "./condition_builder_core.js";
import { createInstructionBuilder } from "./instruction_builder_core.js";

/**
 * Create a response builder UI inside the given container.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Object} opts.data - Element data ({ choices: [...] })
 * @param {Array} opts.variables - Flat variable list
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {Object} opts.linkedPages - Map of screenplay_id → name
 * @param {Function} opts.pushEvent - Callback: pushEvent(eventName, payload)
 * @param {string} opts.elementId - Server element ID (string)
 * @param {Object} [opts.translations] - Optional translation overrides
 * @returns {{ destroy: Function, update: Function, updateLinkedPages: Function }}
 */
export function createResponseBuilder({
  container,
  data,
  variables,
  canEdit,
  linkedPages,
  pushEvent,
  elementId,
  translations,
}) {
  let currentData = data || {};
  let currentLinkedPages = linkedPages || {};
  let childInstances = []; // condition/instruction builder instances

  function getChoices() {
    return currentData.choices || [];
  }

  function destroyChildren() {
    childInstances.forEach((inst) => inst.destroy?.());
    childInstances = [];
  }

  function render() {
    destroyChildren();
    container.innerHTML = "";

    const choices = getChoices();

    // Empty state
    if (choices.length === 0) {
      const empty = document.createElement("div");
      empty.className = "sp-choice-empty";
      empty.textContent = canEdit
        ? "No choices yet. Add one below."
        : "No choices defined";
      container.appendChild(empty);
    }

    // Choice rows
    choices.forEach((choice, idx) => {
      const group = document.createElement("div");
      group.className = "sp-choice-group";
      container.appendChild(group);

      // Main choice row
      const row = document.createElement("div");
      row.className = "sp-choice-row";
      group.appendChild(row);

      // Number
      const num = document.createElement("span");
      num.className = "sp-choice-number";
      num.textContent = `${idx + 1}.`;
      row.appendChild(num);

      // Text input or display
      if (canEdit) {
        const input = document.createElement("input");
        input.type = "text";
        input.value = choice.text || "";
        input.placeholder = "Choice text...";
        input.className = "sp-choice-input";
        input.addEventListener("blur", () => {
          pushEvent("update_response_choice_text", {
            "element-id": elementId,
            "choice-id": choice.id,
            value: input.value,
          });
        });
        row.appendChild(input);
      } else {
        const span = document.createElement("span");
        span.className = "sp-choice-text";
        span.textContent = choice.text || "";
        row.appendChild(span);
      }

      // Linked page controls
      if (choice.linked_screenplay_id) {
        const link = document.createElement("div");
        link.className = "sp-choice-link";

        const navBtn = document.createElement("button");
        navBtn.type = "button";
        navBtn.className = "sp-choice-page-link";
        navBtn.title = "Go to linked page";
        navBtn.addEventListener("click", () => {
          pushEvent("navigate_to_linked_page", {
            "element-id": elementId,
            "choice-id": choice.id,
          });
        });

        const fileIcon = createElement(FileText, { width: 12, height: 12 });
        navBtn.appendChild(fileIcon);

        const pageName = document.createElement("span");
        pageName.className = "sp-choice-page-name";
        const linkedId = choice.linked_screenplay_id;
        pageName.textContent = currentLinkedPages[linkedId] || "(deleted)";
        navBtn.appendChild(pageName);
        link.appendChild(navBtn);

        if (canEdit) {
          const unlinkBtn = document.createElement("button");
          unlinkBtn.type = "button";
          unlinkBtn.className = "sp-choice-unlink";
          unlinkBtn.title = "Unlink page";
          unlinkBtn.appendChild(createElement(Unlink, { width: 12, height: 12 }));
          unlinkBtn.addEventListener("click", () => {
            pushEvent("unlink_choice_screenplay", {
              "element-id": elementId,
              "choice-id": choice.id,
            });
          });
          link.appendChild(unlinkBtn);
        }

        row.appendChild(link);
      } else if (canEdit) {
        const createBtn = document.createElement("button");
        createBtn.type = "button";
        createBtn.className = "sp-choice-create-page";
        createBtn.title = "Create page for this choice";
        createBtn.appendChild(createElement(FilePlus, { width: 12, height: 12 }));
        createBtn.addEventListener("click", () => {
          pushEvent("create_linked_page", {
            "element-id": elementId,
            "choice-id": choice.id,
          });
        });
        row.appendChild(createBtn);
      }

      // Condition toggle
      if (canEdit) {
        const condToggle = document.createElement("button");
        condToggle.type = "button";
        condToggle.className = `sp-choice-toggle ${choice.condition ? "sp-choice-toggle-active" : ""}`;
        condToggle.title = "Toggle condition";
        condToggle.appendChild(createElement(GitBranch, { width: 12, height: 12 }));
        condToggle.addEventListener("click", () => {
          pushEvent("toggle_choice_condition", {
            "element-id": elementId,
            "choice-id": choice.id,
          });
        });
        row.appendChild(condToggle);

        // Instruction toggle
        const instrToggle = document.createElement("button");
        instrToggle.type = "button";
        instrToggle.className = `sp-choice-toggle ${choice.instruction ? "sp-choice-toggle-active" : ""}`;
        instrToggle.title = "Toggle instruction";
        instrToggle.appendChild(createElement(Zap, { width: 12, height: 12 }));
        instrToggle.addEventListener("click", () => {
          pushEvent("toggle_choice_instruction", {
            "element-id": elementId,
            "choice-id": choice.id,
          });
        });
        row.appendChild(instrToggle);

        // Remove button
        const removeBtn = document.createElement("button");
        removeBtn.type = "button";
        removeBtn.className = "sp-choice-remove";
        removeBtn.appendChild(createElement(X, { width: 12, height: 12 }));
        removeBtn.addEventListener("click", () => {
          pushEvent("remove_response_choice", {
            "element-id": elementId,
            "choice-id": choice.id,
          });
        });
        row.appendChild(removeBtn);
      }

      // Nested condition builder
      if (choice.condition) {
        const condExtras = document.createElement("div");
        condExtras.className = "sp-choice-extras";
        group.appendChild(condExtras);

        const condInstance = createConditionBuilder({
          container: condExtras,
          condition: choice.condition,
          variables,
          canEdit,
          context: { "element-id": elementId, "choice-id": choice.id },
          eventName: "update_response_choice_condition",
          pushEvent: (name, payload) => pushEvent(name, payload),
          translations,
        });
        childInstances.push(condInstance);
      }

      // Nested instruction builder
      if (choice.instruction) {
        const instrExtras = document.createElement("div");
        instrExtras.className = "sp-choice-extras";
        group.appendChild(instrExtras);

        const instrInstance = createInstructionBuilder({
          container: instrExtras,
          assignments: choice.instruction,
          variables,
          canEdit,
          context: { "element-id": elementId, "choice-id": choice.id },
          eventName: "update_response_choice_instruction",
          pushEvent: (name, payload) => pushEvent(name, payload),
          translations,
        });
        childInstances.push(instrInstance);
      }
    });

    // Add choice button
    if (canEdit) {
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className = "sp-add-choice";
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(" Add choice");
      addBtn.addEventListener("click", () => {
        pushEvent("add_response_choice", { "element-id": elementId });
      });
      container.appendChild(addBtn);
    }
  }

  // Initial render
  render();

  return {
    destroy() {
      destroyChildren();
      container.innerHTML = "";
    },
    update(newData) {
      currentData = newData || {};
      render();
    },
    updateLinkedPages(newLinkedPages) {
      currentLinkedPages = newLinkedPages || {};
      render();
    },
  };
}
