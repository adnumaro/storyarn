const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [value, setValue] = React.useState("dialogue");
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 240, minHeight: 320 }}>
      <DS.Select
        value={value}
        onChange={setValue}
        options={[
          { label: "Node types", options: [
            { value: "dialogue", label: "Dialogue" },
            { value: "condition", label: "Condition" },
            { value: "instruction", label: "Instruction" },
          ]},
          { label: "Structure", options: [
            { value: "hub", label: "Hub" },
            { value: "jump", label: "Jump" },
            { value: "subflow", label: "Subflow", disabled: true },
          ]},
        ]}
        defaultOpen
      />
      <DS.Select
        placeholder="Pick a language…"
        size="sm"
        options={[
          { value: "en", label: "English" },
          { value: "es", label: "Spanish" },
        ]}
      />
    </div>
  );
}

window.__dsDemo = Demo;
