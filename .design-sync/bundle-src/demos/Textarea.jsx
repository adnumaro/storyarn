const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [text, setText] = React.useState(
    "Mira lowers the lantern. The vault was already open when they arrived.",
  );
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 320 }}>
      <DS.Textarea value={text} onChange={setText} rows={3} />
      <DS.Textarea placeholder="Describe this scene…" rows={2} />
    </div>
  );
}

window.__dsDemo = Demo;
