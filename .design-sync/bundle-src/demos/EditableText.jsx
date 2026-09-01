const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [title, setTitle] = React.useState("The Vault");
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, maxWidth: 280 }}>
      <DS.EditableText value={title} onChange={setTitle} displayClass="text-lg font-semibold" />
      <div style={{ fontSize: 12, color: "hsl(var(--muted-foreground))" }}>
        Click the title to edit it in place.
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
