const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [on, setOn] = React.useState(true);
  const row = { display: "flex", alignItems: "center", gap: 10 };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div style={row}>
        <DS.Switch checked={on} onCheckedChange={setOn} id="autosave" />
        <DS.Label htmlFor="autosave">Autosave</DS.Label>
      </div>
      <div style={row}>
        <DS.Switch checked={false} />
        <DS.Label>Public project</DS.Label>
      </div>
      <div style={row}>
        <DS.Switch checked disabled />
        <DS.Label>Locked by plan</DS.Label>
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
