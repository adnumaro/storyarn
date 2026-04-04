<script setup>
import { computed } from "vue";

// Define the hardcoded steps mimicking the original HEEx layout
const steps = [
  {
    num: "01",
    title: "Define el mundo",
    desc: "Modela personajes, facciones, objetos y reglas narrativas en bases de datos que alimentan al resto de herramientas.",
  },
  {
    num: "02",
    title: "Escribe y ramifica",
    desc: "Construye diálogos, condiciones, instrucciones y flujos secundarios en un editor visual preparado para escala de producción.",
  },
  {
    num: "03",
    title: "Explora y depura",
    desc: "Recorre escenas, ejecuta el Story Player y usa el modo debug para validar lógica y ritmo de la historia fluidamente.",
  },
  {
    num: "04",
    title: "Localiza y exporta",
    desc: "Lleva tus textos, guiones, variables y variables a tu motor — localizados y listos para entrar en producción.",
  },
];
</script>

<template>
  <section
    class="lp-auto-section scroll-mt-32 py-16 lg:py-20"
  >
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <!-- Section header -->
      <div class="mb-8 grid max-w-[56rem] gap-4">
        <h2
          class="text-[clamp(2.2rem,3vw,3.8rem)] font-bold leading-[0.97] tracking-[-0.06em] text-foreground"
        >
          Del worldbuilding al juego publicado
        </h2>
        <p class="max-w-[36rem] text-base leading-relaxed text-muted-foreground">
          Un flujo de trabajo conectado desde la preproducción hasta la exportación — sin necesidad de módulos o herramientas desconectadas.
        </p>
      </div>

      <!-- Stepper grid -->
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <article
          v-for="step in steps"
          :key="step.num"
          class="relative rounded-3xl border border-border/40 bg-muted/60 px-5 pb-6 pt-16 backdrop-blur-md transition-colors hover:border-border/80 hover:bg-muted/80"
        >
          <span class="absolute left-5 top-5 text-3xl font-extrabold tracking-tight text-foreground/20">
            {{ step.num }}
          </span>
          <h3 class="mb-3 text-lg font-bold tracking-tight text-foreground">
            {{ step.title }}
          </h3>
          <p class="leading-relaxed text-muted-foreground">{{ step.desc }}</p>
        </article>
      </div>
    </div>
  </section>
</template>
