const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [value, setValue] = React.useState("editor");
  return (
    <DS.RadioGroup
      value={value}
      onChange={setValue}
      options={[
        { value: "owner", label: "Owner — full control" },
        { value: "editor", label: "Editor — can edit content" },
        { value: "viewer", label: "Viewer — read only" },
      ]}
    />
  );
}

window.__dsDemo = Demo;
