<script setup>
import { Bug, GitBranch, Languages, Map, Package, Table2 } from "lucide-vue-next";

// Define the static features array explicitly matching Staging UX
const features = [
  {
    num: "01",
    icon: Table2,
    title: "Documentos como fuente de verdad",
    desc: "Personajes, facciones, misiones y objetos viven en documentos estructurados con variables, fórmulas y herencia — tu única fuente de verdad.",
    colorClassText: "text-primary",
    colorClassBg: "bg-primary/10",
  },
  {
    num: "02",
    icon: GitBranch,
    title: "Flujos que puedes jugar",
    desc: "Construye diálogos ramificados, juégalos, depúralos y verifícalos — sin salir nunca del editor.",
    colorClassText: "text-accent",
    colorClassBg: "bg-accent/10",
  },
  {
    num: "03",
    icon: Map,
    title: "Escenas con exploración real",
    desc: "Coloca zonas, pins y disparadores en un lienzo interactivo. Camina a través de tu mundo antes de exportarlo al motor.",
    colorClassText: "text-secondary",
    colorClassBg: "bg-secondary/10",
  },
  {
    num: "04",
    icon: Bug,
    title: "Juégalo. Depúralo. Envíalo.",
    desc: "Experimenta la historia como lo haría un jugador o analízala paso a paso viendo cada variable y condición interna en vivo.",
    colorClassText: "text-primary",
    colorClassBg: "bg-primary/10",
  },
  {
    num: "05",
    icon: Languages,
    title: "Localización integrada",
    desc: "Extrae líneas, traduce inteligentemente, maneja glosarios y haz seguimiento de la cobertura por idioma — todo desde el mismo proyecto.",
    colorClassText: "text-accent",
    colorClassBg: "bg-accent/10",
  },
  {
    num: "06",
    icon: Package,
    title: "Exporta a múltiples motores",
    desc: "Exporta de forma nativa a Godot Dialogic, Unity, Unreal, Ink o Yarn Spinner — tu narrativa lista para entrar a producción.",
    colorClassText: "text-secondary",
    colorClassBg: "bg-secondary/10",
  },
];
</script>

<template>
  <section
    id="features-section"
    class="relative z-20 flex min-h-svh items-center bg-linear-to-b from-background via-background to-background"
  >
    <div
      class="lp-features-shell mx-auto w-[min(calc(100%-48px),1280px)] py-28"
      data-feature-stage-shell
    >
      <!-- Section header -->
      <div class="mb-8 max-w-[56rem]" data-feature-intro>
        <h2
          class="text-[clamp(2.2rem,3vw,3.8rem)] font-bold leading-[0.97] tracking-[-0.06em] text-foreground"
        >
          Una plataforma, todo conectado
        </h2>
        <p class="mt-4 max-w-[36rem] text-base leading-relaxed text-muted-foreground">
          Cada herramienta está diseñada para alimentar al resto — logrando que tus personajes, lógica, mundos y traducciones se mantengan conectados en lugar de esparcidos a lo largo de multitud de archivos inconexos.
        </p>
      </div>

      <!-- Feature cards grid -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <article
          v-for="feature in features"
          :key="feature.num"
          data-feature-card
          class="lp-feature-card rounded-3xl border border-border/40 bg-muted/60 p-5 backdrop-blur-md transition-all sm:p-6"
        >
          <em
            class="mb-4 inline-flex min-h-[46px] min-w-[46px] items-center justify-center rounded-xl not-italic"
            :class="[feature.colorClassText, feature.colorClassBg]"
          >
            <component :is="feature.icon" class="size-5" />
          </em>
          <h3 class="mb-3 text-xl font-bold tracking-tight text-foreground">
            {{ feature.title }}
          </h3>
          <p class="leading-relaxed text-muted-foreground">{{ feature.desc }}</p>
        </article>
      </div>
    </div>
  </section>
</template>

<style scoped>
/* Additional micro-interactions matching staging */
@media (hover: hover) {
  .lp-feature-card:hover {
    box-shadow: 0 12px 40px -10px rgba(0, 0, 0, 0.4);
    border-color: hsl(var(--border) / 0.8);
    transform: translateY(-2px);
  }
}
</style>
