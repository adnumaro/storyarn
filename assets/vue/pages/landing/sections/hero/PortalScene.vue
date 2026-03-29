<script setup>
/**
 * Portal shader scene rendered inside a TresCanvas.
 * Full-screen quad with custom shader for the energy ring effect.
 */
import { useLoop } from "@tresjs/core";
import { AdditiveBlending } from "three";

const vertexShader = `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position, 1.0);
}`;

const fragmentShader = `
uniform float uTime;
uniform float uIntensity;
uniform float uScale;
uniform vec2 uResolution;
uniform vec2 uPortalCenter;
uniform float uPortalMaxWidth;
varying vec2 vUv;

void main() {
  vec2 pixel = vUv * uResolution;
  vec2 center = uPortalCenter;
  float dist = length(pixel - center);
  float radius = uPortalMaxWidth * 0.5 * uScale;
  float ring = smoothstep(radius - 60.0, radius, dist) * smoothstep(radius + 60.0, radius, dist);
  float glow = exp(-dist * dist / (radius * radius * 0.8)) * 0.3;
  float pulse = sin(uTime * 1.5) * 0.15 + 0.85;
  float alpha = (ring * 1.2 + glow) * uIntensity * pulse;
  vec3 color = mix(vec3(0.5, 0.3, 1.0), vec3(0.2, 0.8, 0.9), ring);
  gl_FragColor = vec4(color, alpha * 0.6);
}`;

const props = defineProps({
	uniforms: { type: Object, required: true },
	reducedMotion: { type: Boolean, default: false },
});

if (!props.reducedMotion) {
	const { onBeforeRender } = useLoop();
	const startTime = performance.now();
	onBeforeRender(() => {
		props.uniforms.uTime.value = (performance.now() - startTime) / 1000;
	});
}
</script>

<template>
	<TresOrthographicCamera :args="[-1, 1, 1, -1, 0, 1]" />
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
</template>
