const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [pressed, setPressed] = React.useState(true);
  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
      <DS.Toggle pressed={pressed} onPressedChange={setPressed}>
        Bold
      </DS.Toggle>
      <DS.Toggle pressed={false}>Italic</DS.Toggle>
      <DS.Toggle pressed disabled>
        Locked
      </DS.Toggle>
    </div>
  );
}

window.__dsDemo = Demo;
