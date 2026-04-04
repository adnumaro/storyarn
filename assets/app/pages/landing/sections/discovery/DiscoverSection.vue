<script setup>
import { computed, defineAsyncComponent, ref, onMounted } from "vue";

const DiscoverMonitor = defineAsyncComponent(() => import("./DiscoverMonitor.vue"));

const activeTab = ref(0);

onMounted(() => {
  window.addEventListener("storyarn:discover-step", (e) => {
    activeTab.value = e.detail;
  });
});
const isRevealed = ref(true); // GSAP controls the timeline now, assume it's revealed when reached

const features = computed(() => [
  {
    id: "sheets",
    label: "Fichas",
    title: "La herencia mantiene tu mundo consistente",
    desc: "Las fichas padre e hijo te permiten desarrollar personajes, facciones y lugares sin duplicar estructuras constantemente.",
    items: [
      "Variables compartidas que fluyen por la jerarquía.",
      "Sobrescribe solo lo que cambie — por variante o episodio.",
      "Escala el mundo sin copiar y pegar."
    ],
    textPosition: "left",
  },
  {
    id: "flows",
    label: "Flujos",
    title: "Grafos visuales limpios a escala productiva",
    desc: "Diálogos, condiciones, instrucciones y ramas en un único grafo integrado — diseñado para mantenerse claro incluso en máxima escala.",
    items: [
      "Conversaciones, cambios de estado y salidas unificadas.",
      "La lógica vive enlazada a tus fichas, no en fragmentos huérfanos.",
      "Desde bocetos rápidos hasta grafos hipercomplejos."
    ],
    textPosition: "right",
  },
  {
    id: "scenes",
    label: "Escenas",
    title: "Capas y niebla para mapas comprensibles",
    desc: "Utiliza capas para plantear progresiones, visibilidad y estructuras sin aplanar todo en una única imagen saturada.",
    items: [
      "Visibilidad por capas en lugar de un lienzo caótico.",
      "Niebla de guerra para comunicar progresión.",
      "Los grandes espacios se mantienen iterables y legibles en review."
    ],
    textPosition: "center",
  },
]);
</script>

<template>
  <section id="discover" class="discover-section relative min-h-svh w-full">
    <div class="discover-sticky relative h-svh w-full overflow-hidden">
      <!-- 3D Monitor canvas backdrop -->
      <div class="discover-canvas-wrap">
        <DiscoverMonitor :active-step="activeTab" :is-visible="isRevealed" />
      </div>

      <!-- Content stage -->
      <div class="discover-stage" :class="{ 'is-entered': isRevealed }">
        <!-- Text overlays -->
        <div
          v-for="(feature, i) in features"
          :key="feature.id"
          class="discover-text"
          :class="[`discover-text--${feature.textPosition}`, { 'is-active': activeTab === i }]"
        >
          <span class="text-xs font-bold uppercase tracking-widest text-primary">
            {{ feature.label }}
          </span>
          <h3
            class="mt-2 text-[clamp(1.8rem,2.4vw,2.6rem)] font-bold leading-[0.98] tracking-[-0.04em] text-balance text-foreground"
          >
            {{ feature.title }}
          </h3>
          <p class="mt-3 max-w-[34rem] leading-relaxed text-foreground/70">
            {{ feature.desc }}
          </p>
          <ul class="mx-auto mt-4 grid max-w-[28rem] gap-2.5 text-start">
            <li
              v-for="(item, j) in feature.items"
              :key="j"
              class="relative pl-4 leading-relaxed text-foreground/70"
            >
              <span
                class="absolute left-0 top-[0.7em] size-2 rounded-full bg-primary shadow-[0_0_16px_hsl(var(--primary)/0.36)]"
              />
              {{ item }}
            </li>
          </ul>
        </div>

        <!-- Tab buttons (bottom) -->
        <div class="discover-indicators">
          <button
            v-for="(feature, i) in features"
            :key="feature.id"
            type="button"
            class="discover-tab"
            :class="{ 'is-active': activeTab === i }"
            @click="activeTab = i"
          >
            {{ feature.label }}
          </button>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.discover-section {
  background:
    radial-gradient(circle at 50% -15%, rgb(0 0 0 / 28%), transparent 24%),
    linear-gradient(
      180deg,
      hsl(var(--background)) 0%,
      hsl(var(--background)) 54%,
      hsl(var(--background)) 100%
    );
}

.discover-canvas-wrap {
  position: absolute;
  inset: 0;
  z-index: 0;
  pointer-events: none;
}

.discover-canvas-wrap::after {
  content: "";
  position: absolute;
  inset: 0;
  z-index: 1;
  pointer-events: none;
  background: linear-gradient(
    to top,
    hsl(var(--background)) 10%,
    hsl(var(--background)) 20%,
    hsl(var(--background) / 0.85) 30%,
    hsl(var(--background) / 0.4) 40%,
    transparent 60%
  );
}

/* Stage fills the sticky container */
.discover-stage {
  position: absolute;
  inset: 0;
  z-index: 10;
  opacity: 0;
  transition: opacity 0.8s cubic-bezier(0.22, 1, 0.36, 1) 0.35s;
}

.discover-stage.is-entered {
  opacity: 1;
}

/* Text overlays */
.discover-text {
  position: absolute;
  z-index: 1;
  top: 50%;
  transform: translateY(-50%) translateX(0);
  max-width: 480px;
  display: grid;
  gap: 4px;
  opacity: 0;
  pointer-events: none;
  transition:
    opacity 420ms cubic-bezier(0.22, 1, 0.36, 1),
    transform 520ms cubic-bezier(0.22, 1, 0.36, 1);
}

.discover-text.is-active {
  opacity: 1;
  pointer-events: auto;
}

/* Position variants */
.discover-text--left {
  left: max(5%, calc((100% - 1280px) / 2));
  transform: translateY(-50%) translateX(-20px);
}
.discover-text--left.is-active {
  transform: translateY(-50%) translateX(0);
}

.discover-text--right {
  right: max(5%, calc((100% - 1280px) / 2));
  transform: translateY(-50%) translateX(20px);
}
.discover-text--right.is-active {
  transform: translateY(-50%) translateX(0);
}

.discover-text--center {
  top: auto;
  bottom: 15%;
  left: 50%;
  transform: translateX(-50%) translateY(20px);
  text-align: center;
  max-width: 600px;
}
.discover-text--center.is-active {
  transform: translateX(-50%) translateY(0);
}

/* Tab indicators — bottom center */
.discover-indicators {
  position: absolute;
  bottom: 5%;
  left: 50%;
  transform: translateX(-50%);
  z-index: 2;
  display: flex;
  gap: 10px;
}

.discover-tab {
  padding: 10px 14px;
  border-radius: 999px;
  border: 1px solid hsl(var(--foreground) / 0.1);
  background: hsl(var(--foreground) / 0.03);
  backdrop-filter: blur(12px);
  color: hsl(var(--foreground));
  opacity: 0.7;
  font-size: 0.88rem;
  font-weight: 700;
  letter-spacing: -0.02em;
  cursor: pointer;
  transition:
    background 180ms ease,
    border-color 180ms ease,
    opacity 180ms ease,
    transform 180ms ease;
}

.discover-tab:hover {
  transform: translateY(-1px);
  opacity: 0.9;
}

.discover-tab.is-active {
  opacity: 1;
  background: hsl(var(--primary));
  color: hsl(var(--primary-foreground));
  border-color: transparent;
}
</style>
