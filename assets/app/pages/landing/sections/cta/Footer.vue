<script setup>
const { translations } = defineProps({
  translations: { type: Object, default: () => ({}) },
});

const year = new Date().getFullYear();
</script>

<template>
  <footer class="landing-footer w-full border-t border-border/10 pb-8 pt-16 bg-[#111318]">
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      
      <!-- Split Structure -->
      <div class="flex flex-col gap-12 sm:flex-row sm:justify-between mb-16">
        
        <!-- Left: Branding, Tagline, Badges -->
        <div class="flex flex-col items-start gap-5 max-w-[26rem]">
          <div class="flex items-center gap-3">
            <img
              :src="'/images/logos/logo-name-white.png'"
              alt="Storyarn"
              class="h-7 w-auto mix-blend-screen opacity-90"
            />
            <span class="rounded-full border border-border/20 bg-muted/30 px-3 py-1 text-[11px] font-semibold text-foreground/70 tracking-wide uppercase">
              Beta privada
            </span>
          </div>
          <p class="text-sm leading-relaxed text-muted-foreground/80">
            Diseña personajes, diálogos, mundos y localización en un solo proyecto conectado. Creado para equipos narrativos que publican historias interactivas.
          </p>
        </div>
        
        <!-- Right: Links Stack -->
        <nav class="flex flex-col gap-3 text-sm font-medium text-muted-foreground/80 pt-2 lg:mr-24">
          <a href="#features-section" class="transition-colors hover:text-foreground">Características</a>
          <a href="#discover" class="transition-colors hover:text-foreground">Descubrir</a>
          <a href="#workflow" class="transition-colors hover:text-foreground">Flujo de trabajo</a>
          <a href="/docs" class="transition-colors hover:text-foreground">Docs</a>
          <a href="/contact" class="transition-colors hover:text-foreground">Contacto</a>
        </nav>
      </div>

      <!-- Bottom Edge -->
      <div class="flex items-center justify-between border-t border-border/10 pt-6 text-sm text-muted-foreground/50">
        <span>Storyarn &middot; {{ year }}</span>
        <span>Beta privada</span>
      </div>
      
    </div>
  </footer>
</template>
