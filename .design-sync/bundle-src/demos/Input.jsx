const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [name, setName] = React.useState("The Vault");
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 280 }}>
      <DS.Input placeholder="Search sheets…" size="sm" />
      <DS.Input value={name} onChange={setName} />
      <DS.Input placeholder="Disabled" disabled />
    </div>
  );
}

window.__dsDemo = Demo;
