/**
 * TipTap Mention Extension — # trigger for referencing sheets/flows.
 * Uses VueRenderer for popup rendering.
 */

import Mention from "@tiptap/extension-mention";
import { VueRenderer } from "@tiptap/vue-3";
import MentionList from "./MentionList.vue";

function escapeAttr(str) {
	return (str || "")
		.replace(/&/g, "&amp;")
		.replace(/"/g, "&quot;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;");
}

/**
 * @param {Object} opts
 * @param {Function} opts.pushEvent — LiveView pushEvent
 * @param {Function} [opts.pushEventTo] — LiveView pushEventTo (optional)
 * @param {string} [opts.phxTarget] — target selector for pushEventTo
 */
export function createMentionExtension({
	pushEvent,
	pushEventTo,
	phxTarget,
} = {}) {
	let mentionDebounce = null;
	let mentionResolve = null;

	return {
		extension: Mention.configure({
			HTMLAttributes: { class: "mention" },
			suggestion: {
				char: "#",
				allowSpaces: false,

				command: ({ editor, range, props: item }) => {
					const $from = editor.state.doc.resolve(range.from);
					const blockNode = $from.parent;

					if (blockNode.type.name === "character") {
						const blockStart = $from.start();
						const blockEnd = $from.end();
						const blockPos = $from.before();

						editor
							.chain()
							.focus()
							.command(({ tr, dispatch }) => {
								if (dispatch) {
									const nameText = editor.schema.text(
										(item.name || item.label || "").toUpperCase(),
									);
									tr.replaceWith(blockStart, blockEnd, nameText);
									tr.setNodeMarkup(blockPos, undefined, {
										...blockNode.attrs,
										sheetId: String(item.id),
									});
								}
								return true;
							})
							.run();

						const elementId = blockNode.attrs.elementId;
						if (elementId) {
							pushEvent("set_character_sheet", {
								id: String(elementId),
								sheet_id: String(item.id),
							});
						}
						return;
					}

					editor
						.chain()
						.focus()
						.deleteRange(range)
						.insertContent([
							{
								type: "mention",
								attrs: { id: item.id, label: item.label || item.name },
							},
							{ type: "text", text: " " },
						])
						.run();
				},

				items: ({ query }) => {
					return new Promise((resolve) => {
						if (mentionDebounce) clearTimeout(mentionDebounce);
						if (mentionResolve) mentionResolve([]);

						const wrappedResolve = (serverItems) => {
							resolve(
								(serverItems || []).map((item) => ({
									...item,
									label: item.label || item.name,
								})),
							);
						};
						mentionResolve = wrappedResolve;

						mentionDebounce = setTimeout(() => {
							const push =
								phxTarget && pushEventTo
									? (ev, payload) => pushEventTo(phxTarget, ev, payload)
									: pushEvent;
							push("mention_suggestions", { query });

							setTimeout(() => {
								if (mentionResolve === wrappedResolve) {
									mentionResolve = null;
									resolve([]);
								}
							}, 2000);
						}, 300);
					});
				},

				render: () => {
					let component;

					return {
						onStart(props) {
							component = new VueRenderer(MentionList, {
								props,
								editor: props.editor,
							});
							if (!props.clientRect) return;
							const rect = props.clientRect();
							if (!rect) return;
							component.element.style.cssText = `position:absolute;left:${rect.left}px;top:${rect.bottom + 8}px;z-index:50;`;
							document.body.appendChild(component.element);
						},
						onUpdate(props) {
							component?.updateProps(props);
							if (!props.clientRect) return;
							const rect = props.clientRect();
							if (rect && component?.element) {
								component.element.style.left = `${rect.left}px`;
								component.element.style.top = `${rect.bottom + 8}px`;
							}
						},
						onKeyDown(props) {
							if (props.event.key === "Escape") {
								component?.destroy();
								return true;
							}
							return component?.ref?.onKeyDown(props) || false;
						},
						onExit() {
							component?.destroy();
						},
					};
				},
			},

			renderHTML({ node }) {
				return [
					"span",
					{
						class: "mention",
						"data-type": escapeAttr(node.attrs.type || "sheet"),
						"data-id": escapeAttr(node.attrs.id),
						"data-label": escapeAttr(node.attrs.label),
						contenteditable: "false",
					},
					`#${escapeAttr(node.attrs.label || "")}`,
				];
			},

			parseHTML() {
				return [
					{
						tag: "span.mention",
						getAttrs: (dom) => ({
							id: dom.getAttribute("data-id"),
							label: dom.getAttribute("data-label"),
							type: dom.getAttribute("data-type"),
						}),
					},
				];
			},
		}),

		/** Call when server responds with mention suggestions */
		resolveMentions(items) {
			if (mentionResolve) {
				mentionResolve(items);
				mentionResolve = null;
			}
		},
	};
}
