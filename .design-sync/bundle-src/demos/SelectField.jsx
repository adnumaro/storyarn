const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [voice, setVoice] = React.useState("mira");
  return (
    <div
      style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 240, minHeight: 130 }}
    >
      <DS.SelectField
        label="Speaker"
        value={voice}
        onChange={setVoice}
        options={[
          { value: "mira", label: "Mira Chen" },
          { value: "warden", label: "The Warden" },
          { value: "hero", label: "Hero" },
        ]}
      />
      <DS.SelectField
        label="Audio profile"
        placeholder="Pick one…"
        options={[
          { value: "clean", label: "Clean studio" },
          { value: "cave", label: "Cave reverb" },
        ]}
      />
    </div>
  );
}

window.__dsDemo = Demo;
