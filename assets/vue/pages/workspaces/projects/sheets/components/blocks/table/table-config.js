import {
	Calendar,
	CircleDot,
	Columns2,
	Hash,
	Link,
	List,
	Sigma,
	ToggleLeft,
	Type,
} from "lucide-vue-next";

export const typeIcons = {
	number: Hash,
	text: Type,
	boolean: ToggleLeft,
	select: CircleDot,
	multi_select: List,
	date: Calendar,
	formula: Sigma,
	reference: Link,
};

export const typeLabels = {
	number: "Number",
	text: "Text",
	boolean: "Boolean",
	select: "Select",
	multi_select: "Multi Select",
	date: "Date",
	reference: "Reference",
	formula: "Formula",
};

export const allTypes = [
	"number",
	"text",
	"boolean",
	"select",
	"multi_select",
	"date",
	"reference",
	"formula",
];

export function typeIcon(type) {
	return typeIcons[type] || Columns2;
}
