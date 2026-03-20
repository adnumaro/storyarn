import { ChevronLeft, ChevronRight, createElement, Image, Plus, Star, Trash2, X } from "lucide";

/**
 * ImageGallery hook — Pure JS overlay for browsing/editing image collections.
 *
 * Data attributes:
 *   data-items              — JSON array of {id, url, original_url, name, notes, filename, is_default}
 *   data-can-edit           — "true" | "false"
 *   data-target             — CSS selector for pushEventTo target (LiveComponent)
 *   data-title              — Gallery title
 *   data-name-placeholder   — Placeholder for name inputs
 *   data-notes-placeholder  — Placeholder for notes textarea
 *   data-upload-input-id    — ID of the hidden file input to trigger uploads
 *   data-empty-message      — Message when no items
 *   data-upload-label       — Upload button label (i18n)
 *   data-name-label         — Name field label (i18n)
 *   data-notes-label        — Notes field label (i18n)
 *   data-delete-text        — Delete button text (i18n)
 *   data-set-default-text   — "Set as default" button text (i18n)
 *   data-default-badge-text — "default" badge text (i18n)
 *   data-default-label-text — "Default" label text (i18n)
 *
 * Events pushed to server:
 *   gallery_update_name  — {id, value}
 *   gallery_update_notes — {id, value}
 *   gallery_delete       — {id}
 *   gallery_set_default  — {id}
 *
 * Listens for: "open-gallery" custom event on this.el
 */
export const ImageGallery = {
  mounted() {
    this._parseData();
    this._overlay = null;
    this._view = null; // "grid" | "single"
    this._currentIndex = 0;
    this._escHandler = (e) => {
      if (e.key === "Escape") this._close();
    };

    // Open gallery on custom event
    this._openHandler = () => this._openGallery();
    this.el.addEventListener("open-gallery", this._openHandler);
  },

  updated() {
    this._parseData();
    if (this._overlay) {
      if (this._view === "grid") {
        this._renderGrid();
      } else if (this._view === "single") {
        // Ensure current index is still valid
        if (this._currentIndex >= this._items.length) {
          this._currentIndex = Math.max(0, this._items.length - 1);
        }
        if (this._items.length === 0) {
          this._renderGrid();
        } else {
          this._renderSingle();
        }
      }
    }
  },

  destroyed() {
    this._close();
    this.el.removeEventListener("open-gallery", this._openHandler);
  },

  // ─── Data ────────────────────────────────────────────────────────────

  _parseData() {
    try {
      this._items = JSON.parse(this.el.dataset.items || "[]");
    } catch {
      this._items = [];
    }
    this._canEdit = this.el.dataset.canEdit === "true";
    this._target = this.el.dataset.target || null;
    this._title = this.el.dataset.title || "Gallery";
    this._namePlaceholder = this.el.dataset.namePlaceholder || "";
    this._notesPlaceholder = this.el.dataset.notesPlaceholder || "";
    this._uploadInputId = this.el.dataset.uploadInputId || null;
    this._emptyMessage = this.el.dataset.emptyMessage || "No images yet.";
    this._uploadLabel = this.el.dataset.uploadLabel || "Add image";
    this._nameLabel = this.el.dataset.nameLabel || "Name";
    this._notesLabel = this.el.dataset.notesLabel || "Notes";
    this._deleteText = this.el.dataset.deleteText || "Delete";
    this._setDefaultText = this.el.dataset.setDefaultText || "Set as default";
    this._defaultBadgeText = this.el.dataset.defaultBadgeText || "default";
    this._defaultLabelText = this.el.dataset.defaultLabelText || "Default";
  },

  _pushEvent(event, payload) {
    if (this._target) {
      this.pushEventTo(this._target, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },

  // ─── Overlay lifecycle ───────────────────────────────────────────────

  _openGallery() {
    if (this._overlay) return;

    this._overlay = document.createElement("div");
    this._overlay.className = "fixed inset-0 z-[9999] flex items-center justify-center";
    this._overlay.style.cssText = "opacity:0; transition:opacity 150ms ease-out";
    requestAnimationFrame(() => {
      this._overlay.style.opacity = "1";
    });

    // Backdrop
    const backdrop = document.createElement("div");
    backdrop.className = "absolute inset-0 bg-black/50";
    backdrop.addEventListener("click", () => this._close());
    this._overlay.appendChild(backdrop);

    // Content container
    this._container = document.createElement("div");
    this._container.className =
      "relative bg-base-200 rounded-xl shadow-2xl border border-base-content/10 w-full max-w-xl max-h-[85vh] overflow-hidden flex flex-col mx-4";
    this._container.style.cssText = "transform:scale(0.95); transition:transform 150ms ease-out";
    requestAnimationFrame(() => {
      this._container.style.transform = "scale(1)";
    });
    this._overlay.appendChild(this._container);

    document.body.appendChild(this._overlay);
    document.addEventListener("keydown", this._escHandler);

    this._view = "grid";
    this._renderGrid();
  },

  _close() {
    if (!this._overlay) return;
    document.removeEventListener("keydown", this._escHandler);
    this._overlay.remove();
    this._overlay = null;
    this._container = null;
    this._view = null;
  },

  // ─── Grid view ───────────────────────────────────────────────────────

  _renderGrid() {
    this._view = "grid";
    const c = this._container;
    c.innerHTML = "";

    // Header
    const header = this._el("div", "flex items-center justify-between px-5 pt-4 pb-3");
    header.appendChild(this._el("h3", "font-bold text-lg", this._title));
    const closeBtn = this._iconButton(X, "btn-ghost btn-sm btn-square");
    closeBtn.addEventListener("click", () => this._close());
    header.appendChild(closeBtn);
    c.appendChild(header);

    // Scrollable body
    const body = this._el("div", "overflow-y-auto px-5 pb-5 flex-1");

    if (this._items.length === 0) {
      // Empty state
      const empty = this._el("div", "text-center py-8 text-base-content/40");
      const icon = createElement(Image, { width: 32, height: 32 });
      icon.classList.add("mx-auto", "mb-2", "opacity-40");
      empty.appendChild(icon);
      const msg = this._el("p", "text-sm", this._emptyMessage);
      empty.appendChild(msg);
      body.appendChild(empty);
    } else {
      // Thumbnail grid
      const grid = this._el("div", "grid grid-cols-3 sm:grid-cols-4 gap-3");

      for (let i = 0; i < this._items.length; i++) {
        const item = this._items[i];
        const card = this._el("div", "group/card relative flex flex-col items-center");

        // Thumbnail button
        const thumbBtn = this._el(
          "button",
          [
            "aspect-square w-full rounded-lg overflow-hidden border-2 transition-colors cursor-pointer",
            "border-base-content/10 hover:border-base-content/30",
          ].join(" "),
        );
        thumbBtn.type = "button";
        const img = document.createElement("img");
        img.src = item.url;
        img.alt = item.name || "";
        img.className = "w-full h-full object-cover";
        thumbBtn.appendChild(img);
        const idx = i;
        thumbBtn.addEventListener("click", () => {
          this._currentIndex = idx;
          this._renderSingle();
        });
        card.appendChild(thumbBtn);

        // Default badge
        if (item.is_default) {
          const badge = this._el("div", "absolute top-1 left-1");
          badge.appendChild(
            this._el("span", "badge badge-primary badge-xs", this._defaultBadgeText),
          );
          card.appendChild(badge);
        }

        // Delete X button
        if (this._canEdit) {
          const delBtn = this._el(
            "button",
            [
              "absolute top-1 right-1 size-5 rounded-full bg-black/70",
              "flex items-center justify-center opacity-0 group-hover/card:opacity-100 transition-opacity",
            ].join(" "),
          );
          delBtn.type = "button";
          delBtn.appendChild(createElement(X, { width: 12, height: 12, color: "white" }));
          delBtn.addEventListener("click", (e) => {
            e.stopPropagation();
            this._pushEvent("gallery_delete", { id: item.id });
          });
          card.appendChild(delBtn);
        }

        // Name input (editable) or label (read-only)
        if (this._canEdit) {
          const nameInput = document.createElement("input");
          nameInput.type = "text";
          nameInput.value = item.name || "";
          nameInput.placeholder = this._namePlaceholder;
          nameInput.className =
            "input input-xs w-full mt-1 text-center text-xs bg-transparent border-0 border-b border-base-content/10 focus:border-primary rounded-none px-0";
          nameInput.addEventListener("blur", () => {
            if (nameInput.value !== (item.name || "")) {
              this._pushEvent("gallery_update_name", { id: item.id, value: nameInput.value });
            }
          });
          card.appendChild(nameInput);
        } else if (item.name) {
          card.appendChild(
            this._el("p", "text-xs text-base-content/60 mt-1 truncate max-w-full", item.name),
          );
        }

        grid.appendChild(card);
      }

      body.appendChild(grid);
    }

    // Upload button
    if (this._canEdit && this._uploadInputId) {
      const uploadWrap = this._el("div", "mt-4");
      const uploadLabel = document.createElement("label");
      uploadLabel.htmlFor = this._uploadInputId;
      uploadLabel.className =
        "btn btn-ghost btn-sm w-full border border-dashed border-base-content/20 cursor-pointer";
      uploadLabel.appendChild(createElement(Plus, { width: 16, height: 16 }));
      uploadLabel.appendChild(document.createTextNode(` ${this._uploadLabel}`));
      uploadWrap.appendChild(uploadLabel);
      body.appendChild(uploadWrap);
    }

    c.appendChild(body);
  },

  // ─── Single view ─────────────────────────────────────────────────────

  _renderSingle() {
    this._view = "single";
    const c = this._container;
    c.innerHTML = "";

    const item = this._items[this._currentIndex];
    if (!item) return this._renderGrid();

    const count = this._items.length;

    // Header: back + nav
    const header = this._el("div", "flex items-center justify-between px-5 pt-4 pb-3");

    const backBtn = this._el("button", "btn btn-ghost btn-sm gap-1");
    backBtn.type = "button";
    backBtn.appendChild(createElement(ChevronLeft, { width: 16, height: 16 }));
    backBtn.appendChild(document.createTextNode(this._title));
    backBtn.addEventListener("click", () => this._renderGrid());
    header.appendChild(backBtn);

    if (count > 1) {
      const nav = this._el("div", "flex items-center gap-1");
      const prevBtn = this._iconButton(ChevronLeft, "btn-ghost btn-xs btn-square");
      prevBtn.addEventListener("click", () => this._navigate(-1));
      nav.appendChild(prevBtn);

      nav.appendChild(
        this._el("span", "text-xs text-base-content/40", `${this._currentIndex + 1}/${count}`),
      );

      const nextBtn = this._iconButton(ChevronRight, "btn-ghost btn-xs btn-square");
      nextBtn.addEventListener("click", () => this._navigate(1));
      nav.appendChild(nextBtn);

      header.appendChild(nav);
    }

    c.appendChild(header);

    // Scrollable body
    const body = this._el("div", "overflow-y-auto px-5 pb-5 flex-1");

    // Image
    const imgWrap = this._el(
      "div",
      "flex justify-center bg-base-300/20 rounded-lg overflow-hidden mb-4",
    );
    const img = document.createElement("img");
    img.src = item.original_url || item.url;
    img.alt = item.name || "";
    img.className = "max-w-full max-h-[55vh] object-contain";
    imgWrap.appendChild(img);
    body.appendChild(imgWrap);

    // Filename
    if (item.filename) {
      body.appendChild(this._el("p", "text-xs text-base-content/40 truncate mb-3", item.filename));
    }

    // Name field
    const nameGroup = this._el("div", "mb-3");
    nameGroup.appendChild(this._el("label", "label text-xs font-medium", this._nameLabel));
    const nameInput = document.createElement("input");
    nameInput.type = "text";
    nameInput.value = item.name || "";
    nameInput.placeholder = this._namePlaceholder;
    nameInput.disabled = !this._canEdit;
    nameInput.className = "input input-sm input-bordered w-full";
    nameInput.addEventListener("blur", () => {
      if (nameInput.value !== (item.name || "")) {
        this._pushEvent("gallery_update_name", { id: item.id, value: nameInput.value });
        // Update local state so navigation doesn't lose the edit
        item.name = nameInput.value;
      }
    });
    nameGroup.appendChild(nameInput);
    body.appendChild(nameGroup);

    // Notes field
    const notesGroup = this._el("div", "mb-3");
    notesGroup.appendChild(this._el("label", "label text-xs font-medium", this._notesLabel));
    const notesInput = document.createElement("textarea");
    notesInput.rows = 3;
    notesInput.placeholder = this._notesPlaceholder;
    notesInput.disabled = !this._canEdit;
    notesInput.className = "textarea textarea-sm textarea-bordered w-full";
    notesInput.value = item.notes || "";
    notesInput.addEventListener("blur", () => {
      if (notesInput.value !== (item.notes || "")) {
        this._pushEvent("gallery_update_notes", { id: item.id, value: notesInput.value });
        item.notes = notesInput.value;
      }
    });
    notesGroup.appendChild(notesInput);
    body.appendChild(notesGroup);

    // Footer: actions + delete
    const footer = this._el(
      "div",
      "flex items-center justify-between pt-3 border-t border-base-content/10",
    );

    const actions = this._el("div", "flex items-center gap-2");

    if (this._canEdit && !item.is_default) {
      const defaultBtn = this._el("button", "btn btn-sm btn-ghost gap-1");
      defaultBtn.type = "button";
      defaultBtn.appendChild(createElement(Star, { width: 14, height: 14 }));
      defaultBtn.appendChild(document.createTextNode(this._setDefaultText));
      defaultBtn.addEventListener("click", () => {
        this._pushEvent("gallery_set_default", { id: item.id });
      });
      actions.appendChild(defaultBtn);
    } else if (item.is_default) {
      actions.appendChild(this._el("span", "badge badge-primary badge-sm", this._defaultLabelText));
    }

    footer.appendChild(actions);

    if (this._canEdit) {
      const deleteBtn = this._el("button", "btn btn-sm btn-error btn-outline gap-1");
      deleteBtn.type = "button";
      deleteBtn.appendChild(createElement(Trash2, { width: 14, height: 14 }));
      deleteBtn.appendChild(document.createTextNode(this._deleteText));
      deleteBtn.addEventListener("click", () => {
        this._pushEvent("gallery_delete", { id: item.id });
      });
      footer.appendChild(deleteBtn);
    }

    body.appendChild(footer);
    c.appendChild(body);
  },

  _navigate(direction) {
    const count = this._items.length;
    if (count <= 1) return;
    this._currentIndex = (this._currentIndex + direction + count) % count;
    this._renderSingle();
  },

  // ─── DOM helpers ─────────────────────────────────────────────────────

  _el(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text) el.textContent = text;
    return el;
  },

  _iconButton(Icon, className) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = `btn ${className}`;
    btn.appendChild(createElement(Icon, { width: 16, height: 16 }));
    return btn;
  },
};
