const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [label, setLabel] = React.useState("mira_intro");
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 260 }}>
      <DS.TextField label="Node label" value={label} onChange={setLabel} />
      <DS.TextField label="Shortcut" placeholder="e.g. hero" />
      <DS.TextField label="Locked" value="vault_open" disabled />
    </div>
  );
}

window.__dsDemo = Demo;
