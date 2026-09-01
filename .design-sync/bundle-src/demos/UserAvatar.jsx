const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
      <DS.UserAvatar displayName="Mira Chen" size="lg" />
      <DS.UserAvatar displayName="Adrián N" color="#2dd4bf" size="md" />
      <DS.UserAvatar email="writer@storyarn.app" size="sm" />
      <DS.UserAvatar displayName="Kai" size="xs" color="#f59e0b" />
    </div>
  );
}

window.__dsDemo = Demo;
