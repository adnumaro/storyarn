const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [key, setKey] = React.useState("sk-ant-a0b1c2d3e4f5");
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6, maxWidth: 280 }}>
      <DS.Label htmlFor="api-key">Provider API key</DS.Label>
      <DS.PasswordInput id="api-key" value={key} onChange={setKey} />
    </div>
  );
}

window.__dsDemo = Demo;
