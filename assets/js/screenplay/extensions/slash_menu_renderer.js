/**
 * SlashMenuRenderer — vanilla JS floating menu for the slash command palette.
 *
 * Reuses existing CSS classes from screenplay.css (.slash-menu, .slash-menu-item, etc.).
 * Renders command items with Lucide icons, keyboard navigation, and filtering.
 */

import {
  createElement,
  Clapperboard,
  AlignLeft,
  User,
  MessageSquare,
  Parentheses,
  ArrowRight,
  GitBranch,
  Zap,
  List,
  StickyNote,
  Heading,
  Scissors,
} from "lucide";
import { positionPopup } from "../utils.js";

const ICONS = {
  clapperboard: Clapperboard,
  "align-left": AlignLeft,
  user: User,
  "message-square": MessageSquare,
  parentheses: Parentheses,
  "arrow-right": ArrowRight,
  "git-branch": GitBranch,
  zap: Zap,
  list: List,
  "sticky-note": StickyNote,
  heading: Heading,
  scissors: Scissors,
};

const GROUP_LABELS = {
  screenplay: "Screenplay",
  interactive: "Interactive",
  utility: "Utility",
};

/**
 * Creates a Suggestion render() lifecycle object for the slash menu.
 */
export function slashMenuRenderer() {
  let popup = null;
  let selectedIndex = 0;
  let currentItems = [];
  let currentProps = null;

  function updateHighlight() {
    if (!popup) return;
    const buttons = popup.querySelectorAll(".slash-menu-item");
    buttons.forEach((btn, i) => {
      btn.classList.toggle("highlighted", i === selectedIndex);
      if (i === selectedIndex) {
        btn.scrollIntoView({ block: "nearest" });
      }
    });
  }

  function renderItems(items, props) {
    currentItems = items;
    currentProps = props;
    selectedIndex = 0;

    const list = popup.querySelector(".slash-menu-list");
    list.innerHTML = "";

    if (items.length === 0) {
      const empty = document.createElement("div");
      empty.className = "slash-menu-group-label";
      empty.textContent = "No results";
      list.appendChild(empty);
      return;
    }

    // Group items by category, preserving order
    const grouped = new Map();
    for (const item of items) {
      if (!grouped.has(item.group)) grouped.set(item.group, []);
      grouped.get(item.group).push(item);
    }

    for (const [groupKey, groupItems] of grouped) {
      const groupEl = document.createElement("div");
      groupEl.className = "slash-menu-group";

      const label = document.createElement("div");
      label.className = "slash-menu-group-label";
      label.textContent = GROUP_LABELS[groupKey] || groupKey;
      groupEl.appendChild(label);

      for (const item of groupItems) {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "slash-menu-item";

        const IconComponent = ICONS[item.icon];
        if (IconComponent) {
          const icon = createElement(IconComponent, { width: 16, height: 16 });
          icon.classList.add("slash-menu-item-icon");
          btn.appendChild(icon);
        }

        const textContainer = document.createElement("div");
        textContainer.className = "slash-menu-item-text";

        const labelSpan = document.createElement("span");
        labelSpan.className = "slash-menu-item-label";
        labelSpan.textContent = item.label;
        textContainer.appendChild(labelSpan);

        const descSpan = document.createElement("span");
        descSpan.className = "slash-menu-item-desc";
        descSpan.textContent = item.desc;
        textContainer.appendChild(descSpan);

        btn.appendChild(textContainer);

        btn.addEventListener("click", () => {
          props.command(item);
        });

        groupEl.appendChild(btn);
      }

      list.appendChild(groupEl);
    }

    updateHighlight();
  }

  return {
    onStart(props) {
      popup = document.createElement("div");
      popup.className = "slash-menu";

      const list = document.createElement("div");
      list.className = "slash-menu-list";
      popup.appendChild(list);

      document.body.appendChild(popup);

      renderItems(props.items, props);
      positionPopup(popup, props);
    },

    onUpdate(props) {
      if (!popup) return;
      renderItems(props.items, props);
      positionPopup(popup, props);
    },

    onKeyDown({ event }) {
      if (event.key === "ArrowUp") {
        event.preventDefault();
        if (currentItems.length > 0) {
          selectedIndex =
            (selectedIndex - 1 + currentItems.length) % currentItems.length;
          updateHighlight();
        }
        return true;
      }

      if (event.key === "ArrowDown") {
        event.preventDefault();
        if (currentItems.length > 0) {
          selectedIndex = (selectedIndex + 1) % currentItems.length;
          updateHighlight();
        }
        return true;
      }

      if (event.key === "Enter") {
        event.preventDefault();
        if (currentItems[selectedIndex] && currentProps) {
          currentProps.command(currentItems[selectedIndex]);
        }
        return true;
      }

      if (event.key === "Escape") {
        popup?.remove();
        popup = null;
        return true;
      }

      return false;
    },

    onExit() {
      popup?.remove();
      popup = null;
    },
  };
}

