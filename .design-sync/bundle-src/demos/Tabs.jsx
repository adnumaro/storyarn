const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [tab, setTab] = React.useState("variables");
  const panels = {
    variables: "12 variables defined on this sheet.",
    usages: "Referenced by 4 flows and 2 scenes.",
    history: "Last change 2 hours ago by Mira.",
  };
  return (
    <div style={{ maxWidth: 340 }}>
      <DS.Tabs
        value={tab}
        onChange={setTab}
        tabs={[
          { value: "variables", label: "Variables" },
          { value: "usages", label: "Usages" },
          { value: "history", label: "History" },
        ]}
      >
        <div
          style={{
            padding: "14px 4px",
            fontSize: 13,
            color: "hsl(var(--muted-foreground))",
          }}
        >
          {panels[tab]}
        </div>
      </DS.Tabs>
    </div>
  );
}

window.__dsDemo = Demo;
