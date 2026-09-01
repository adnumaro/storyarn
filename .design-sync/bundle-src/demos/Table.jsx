const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ maxWidth: 480 }}>
      <DS.Table
        columns={[
          { key: "name", label: "Flow" },
          { key: "nodes", label: "Nodes", class: "text-right" },
          { key: "health", label: "Health" },
          { key: "updated", label: "Updated" },
        ]}
        rows={[
          { name: "The Vault", nodes: 24, health: "OK", updated: "2h ago" },
          { name: "Mira's Path", nodes: 61, health: "2 warnings", updated: "yesterday" },
          { name: "Ferry Crossing", nodes: 18, health: "1 error", updated: "3d ago" },
        ]}
      />
    </div>
  );
}

window.__dsDemo = Demo;
