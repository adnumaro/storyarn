export interface FlowTreeItem {
  id: number | string;
  name: string;
  is_main?: boolean;
  children?: FlowTreeItem[];
}

export interface DnDDropEvent {
  draggedItems: { item: FlowTreeItem; items: FlowTreeItem[] }[];
  hoveredDraggable: { item: FlowTreeItem; items: FlowTreeItem[]; element: HTMLElement } | null;
  dropZone: { items: FlowTreeItem[] } | null;
  provider: { pointer: { value: { current: { x: number; y: number } } } } | null;
  helpers: {
    suggestSort: (
      dir: string,
    ) => { sourceItems: FlowTreeItem[]; targetItems: FlowTreeItem[]; sameList: boolean } | null;
  };
}
