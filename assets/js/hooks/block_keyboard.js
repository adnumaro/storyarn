/**
 * BlockKeyboard Hook
 *
 * Attached to the blocks container. Listens for keyboard shortcuts
 * when a block is selected (selected_block_id is set), and provides
 * a right-click context menu for block actions.
 *
 * Shortcuts:
 * - Delete/Backspace → delete_block
 * - Cmd+D / Ctrl+D   → duplicate_block
 * - Shift+ArrowUp    → move_block_up
 * - Shift+ArrowDown  → move_block_down
 * - Escape           → deselect_block
 *
 * Context menu (right-click on block):
 * - Duplicate
 * - Go to source      (inherited only)
 * - Detach property   (inherited only)
 * - Hide for children (inherited only)
 * - Delete
 */

import { ArrowUpRight, Copy, createElement, EyeOff, Link, Scissors, Trash2 } from "lucide";

export const BlockKeyboard = {
  mounted() {
    this._menu = null;

    this._handleKeydown = (e) => {
      const tag = e.target.tagName;
      if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA" || e.target.isContentEditable) {
        return;
      }

      const selectedId = this.el.dataset.selectedBlockId;
      if (!selectedId) return;

      const isMod = e.metaKey || e.ctrlKey;

      if (e.key === "Delete" || e.key === "Backspace") {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "delete_block", { id: selectedId });
      } else if (e.key === "d" && isMod) {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "duplicate_block", { id: selectedId });
      } else if (e.key === "ArrowUp" && e.shiftKey) {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "move_block_up", { id: selectedId });
      } else if (e.key === "ArrowDown" && e.shiftKey) {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "move_block_down", { id: selectedId });
      } else if (e.key === "Escape") {
        e.preventDefault();
        this._hideMenu();
        this.pushEventTo(this.el.dataset.phxTarget, "deselect_block", {});
      }
    };

    this._handleContextMenu = (e) => {
      const blockEl = e.target.closest("[data-id]");
      if (!blockEl) return;

      e.preventDefault();
      this._showMenu(blockEl, e.clientX, e.clientY);
    };

    this._handleClickOutside = (e) => {
      if (this._menu && !this._menu.contains(e.target)) {
        this._hideMenu();
      }
    };

    document.addEventListener("keydown", this._handleKeydown);
    this.el.addEventListener("contextmenu", this._handleContextMenu);
    document.addEventListener("mousedown", this._handleClickOutside, true);
  },

  destroyed() {
    document.removeEventListener("keydown", this._handleKeydown);
    this.el.removeEventListener("contextmenu", this._handleContextMenu);
    document.removeEventListener("mousedown", this._handleClickOutside, true);
    this._hideMenu();
  },

  // ---------------------------------------------------------------------------
  // Context menu
  // ---------------------------------------------------------------------------

  _showMenu(blockEl, x, y) {
    this._hideMenu();

    const blockId = blockEl.dataset.id;
    const isInherited = blockEl.dataset.inherited === "true";
    const inheritedFromBlockId = blockEl.dataset.inheritedFromBlockId;
    const target = this.el.dataset.phxTarget;

    const menu = document.createElement("ul");
    menu.className =
      "menu p-2 shadow-lg bg-base-200 border border-base-300 rounded-box w-52 z-[1050]";
    menu.style.position = "fixed";
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;

    // Duplicate
    menu.appendChild(
      this._menuItem(Copy, "Duplicate", () => {
        this.pushEventTo(target, "duplicate_block", { id: blockId });
      }),
    );

    // Inherited actions
    if (isInherited) {
      const isDetached = blockEl.dataset.detached === "true";

      menu.appendChild(this._divider());

      menu.appendChild(
        this._menuItem(ArrowUpRight, "Go to source", () => {
          this.pushEventTo(target, "navigate_to_source", { id: blockId });
        }),
      );

      if (isDetached) {
        menu.appendChild(
          this._menuItem(Link, "Re-attach", () => {
            this.pushEventTo(target, "reattach_block", { id: blockId });
          }),
        );
      } else {
        menu.appendChild(
          this._menuItem(Scissors, "Detach property", () => {
            this.pushEventTo(target, "detach_inherited_block", { id: blockId });
          }),
        );
      }

      if (inheritedFromBlockId) {
        menu.appendChild(
          this._menuItem(EyeOff, "Hide for children", () => {
            this.pushEventTo(target, "hide_inherited_for_children", {
              id: inheritedFromBlockId,
            });
          }),
        );
      }
    }

    // Delete
    menu.appendChild(this._divider());
    menu.appendChild(
      this._menuItem(
        Trash2,
        "Delete",
        () => {
          this.pushEventTo(target, "delete_block", { id: blockId });
        },
        "text-error",
      ),
    );

    document.body.appendChild(menu);
    this._menu = menu;

    // Clamp to viewport
    requestAnimationFrame(() => {
      const rect = menu.getBoundingClientRect();
      if (rect.right > window.innerWidth) {
        menu.style.left = `${window.innerWidth - rect.width - 8}px`;
      }
      if (rect.bottom > window.innerHeight) {
        menu.style.top = `${window.innerHeight - rect.height - 8}px`;
      }
    });
  },

  _hideMenu() {
    if (this._menu) {
      this._menu.remove();
      this._menu = null;
    }
  },

  _menuItem(Icon, label, onClick, extraClass = "") {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    if (extraClass) btn.className = extraClass;

    const icon = createElement(Icon, { width: 16, height: 16 });
    btn.appendChild(icon);
    btn.appendChild(document.createTextNode(` ${label}`));

    btn.addEventListener("click", () => {
      this._hideMenu();
      onClick();
    });

    li.appendChild(btn);
    return li;
  },

  _divider() {
    const div = document.createElement("div");
    div.className = "divider my-0.5";
    return div;
  },
};
