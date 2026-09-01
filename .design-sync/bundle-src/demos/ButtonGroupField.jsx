const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [fit, setFit] = React.useState("cover");
  return (
    <div style={{ maxWidth: 260 }}>
      <DS.ButtonGroupField
        label="Image fit"
        value={fit}
        onChange={setFit}
        options={[
          { value: "cover", label: "Cover" },
          { value: "contain", label: "Contain" },
          { value: "fill", label: "Fill" },
        ]}
      />
    </div>
  );
}

window.__dsDemo = Demo;
