const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [view, setView] = React.useState("canvas");
  const [marks, setMarks] = React.useState(["bold"]);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      <DS.ToggleGroup
        type="single"
        value={view}
        onChange={setView}
        items={[
          { value: "canvas", label: "Canvas" },
          { value: "list", label: "List" },
          { value: "compare", label: "Compare" },
        ]}
      />
      <DS.ToggleGroup
        type="multiple"
        value={marks}
        onChange={setMarks}
        size="sm"
        items={[
          { value: "bold", label: "B" },
          { value: "italic", label: "I" },
          { value: "underline", label: "U" },
        ]}
      />
    </div>
  );
}

window.__dsDemo = Demo;
