const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [val, setVal] = React.useState(true);
  const [tri, setTri] = React.useState(null);
  return (
    <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
      <DS.BooleanToggle value={val} trueLabel="Visible" falseLabel="Hidden" onChange={setVal} />
      <DS.BooleanToggle
        value={tri}
        mode="tri_state"
        trueLabel="Yes"
        falseLabel="No"
        neutralLabel="Unset"
        onChange={setTri}
      />
    </div>
  );
}

window.__dsDemo = Demo;
