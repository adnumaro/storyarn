<script setup lang="ts">
import { useLoop } from "@tresjs/core";
import { AdditiveBlending, type IUniform } from "three";
import { vertexShader, fragmentShader } from "./shaders/portalShader";

interface PortalUniforms {
  uTime: IUniform<number>;
  uIntensity: IUniform<number>;
  uScale: IUniform<number>;
  uResolution: IUniform;
  uPortalCenter: IUniform;
  uPortalMaxWidth: IUniform<number>;
  uDpr: IUniform<number>;
}

const { uniforms, reducedMotion = false } = defineProps<{
  uniforms: PortalUniforms;
  reducedMotion?: boolean;
}>();

if (!reducedMotion) {
  const { onBeforeRender } = useLoop();
  const startTime = performance.now();
  onBeforeRender(() => {
    uniforms.uTime.value = (performance.now() - startTime) / 1000;
  });
}
</script>

<template>
  <TresOrthographicCamera :args="[-1, 1, 1, -1, 0, 1]">
    <TresMesh>
      <TresPlaneGeometry :args="[2, 2]" />
      <TresShaderMaterial
        :vertex-shader="vertexShader"
        :fragment-shader="fragmentShader"
        :uniforms="uniforms"
        :transparent="true"
        :depth-write="false"
        :blending="AdditiveBlending"
      />
    </TresMesh>
  </TresOrthographicCamera>
</template>
