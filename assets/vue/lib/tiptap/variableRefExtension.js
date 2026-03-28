/**
 * TipTap Variable Reference Extension — $ trigger for variable refs.
 * Uses VueRenderer for popup rendering.
 */

import Mention from "@tiptap/extension-mention";
import { VueRenderer } from "@tiptap/vue-3";
import VariableList from "./VariableList.vue";

function escapeAttr(str) {
	return (str || "").replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/**
 * @param {Object} opts
 * @param {Function} opts.pushEvent — LiveView pushEvent
 * @param {Function} [opts.pushEventTo] — LiveView pushEventTo (optional)
 * @param {string} [opts.phxTarget] — target selector for pushEventTo
 */
export function createVariableRefExtension({ pushEvent, pushEventTo, phxTarget } = {}) {
	let variableDebounce = null;
	let variableResolve = null;

	return {
		extension: Mention.extend({ name: "variableRef" }).configure({
			HTMLAttributes: { class: "variable-ref" },
			suggestion: {
				char: "$",
				allowSpaces: false,

				command: ({ editor, range, props: item }) => {
					editor.chain().focus().deleteRange(range).insertContent([
						{ type: "variableRef", attrs: { id: item.ref, label: item.ref, blockType: item.block_type } },
						{ type: "text", text: " " },
					]).run();
				},

				items: ({ query }) => {
					return new Promise((resolve) => {
						if (variableDebounce) clearTimeout(variableDebounce);
						if (variableResolve) variableResolve([]);

						const wrappedResolve = (serverItems) => {
							resolve((serverItems || []).map((item) => ({
								...item,
								label: item.ref,
							})));
						};
						variableResolve = wrappedResolve;

						variableDebounce = setTimeout(() => {
							const push = phxTarget && pushEventTo
								? (ev, payload) => pushEventTo(phxTarget, ev, payload)
								: pushEvent;
							push("variable_suggestions", { query });

							setTimeout(() => {
								if (variableResolve === wrappedResolve) {
									variableResolve = null;
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
							component = new VueRenderer(VariableList, { props, editor: props.editor });
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
							if (props.event.key === "Escape") { component?.destroy(); return true; }
							return component?.ref?.onKeyDown(props) || false;
						},
						onExit() { component?.destroy(); },
					};
				},
			},

			renderHTML({ node }) {
				return ["span", {
					class: "variable-ref",
					"data-ref": escapeAttr(node.attrs.id || ""),
					"data-block-type": escapeAttr(node.attrs.blockType || "text"),
					contenteditable: "false",
				}, `$${escapeAttr(node.attrs.id || "")}`];
			},

			parseHTML() {
				return [{ tag: "span.variable-ref", getAttrs: (dom) => ({
					id: dom.getAttribute("data-ref"),
					label: dom.getAttribute("data-ref"),
					blockType: dom.getAttribute("data-block-type"),
				}) }];
			},
		}),

		/** Call when server responds with variable suggestions */
		resolveVariables(items) {
			if (variableResolve) {
				variableResolve(items);
				variableResolve = null;
			}
		},
	};
}
