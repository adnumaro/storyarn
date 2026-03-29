<script setup>
/**
 * 3D monitor scene rendered inside a TresCanvas.
 * Displays rotating screenshots with GSAP-driven transitions.
 */
import { shallowRef, watch, onMounted } from "vue";
import { useLoop } from "@tresjs/core";
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/examples/jsm/geometries/RoundedBoxGeometry.js";
import { gsap } from "gsap";

const props = defineProps({
	activeStep: { type: Number, default: 0 },
	isVisible: { type: Boolean, default: false },
});

const SCREEN_IMAGES = [
	"/images/landing/discovery-sheets.png",
	"/images/landing/discovery-flows.png",
	"/images/landing/discovery-scenes.png",
];

const SUB_STEPS = [
	{ rotY: -0.58, rotZ: 0.03, posX: 0.75, camZ: 0, yOffset: 0 },
	{ rotY: 0.58, rotZ: -0.03, posX: -0.75, camZ: 0, yOffset: 0 },
	{ rotY: 0, rotZ: 0, posX: 0, camZ: -1.8, yOffset: -1 },
];

const BASE_CAM_Z = 4.8;
const FOV = 40;

// Refs to Three.js instances (via TresJS template refs)
const groupRef = shallowRef(null);
const cameraRef = shallowRef(null);
const screenMatARef = shallowRef(null);
const screenMatBRef = shallowRef(null);

const textures = shallowRef([]);
let prevStep = 0;

// --- Geometry (created once, shared across renders) ---
const screenW = 3.2;
const screenH = 2.0;
const bezelPad = 0.08;
const bezelW = screenW + bezelPad * 2;
const bezelH = screenH + bezelPad * 2;
const bodyDepth = 0.18;

const bodyGeo = new RoundedBoxGeometry(bezelW, bezelH, bodyDepth, 3, 0.04);
const insetGeo = new THREE.PlaneGeometry(screenW + 0.02, screenH + 0.02);
const screenGeoA = new THREE.PlaneGeometry(screenW, screenH);
const screenGeoB = new THREE.PlaneGeometry(screenW, screenH);

// --- Initial position for step 0 ---
const step0 = SUB_STEPS[0];
const fovRad = (FOV * Math.PI) / 180;
const initialVisibleH = 2 * Math.tan(fovRad / 2) * BASE_CAM_Z;
const initialY = -(initialVisibleH / 2) + 1.6;

// Screen layer Z positions (relative to body front)
const screenAZ = bodyDepth / 2 + 0.005;
const screenBZ = bodyDepth / 2 + 0.006;
const insetZ = bodyDepth / 2 + 0.003;

// --- Texture loading ---
onMounted(() => {
	const loader = new THREE.TextureLoader();
	const loaded = [];

	SCREEN_IMAGES.forEach((src, i) => {
		loader.load(
			src,
			(tex) => {
				tex.colorSpace = THREE.SRGBColorSpace;
				tex.minFilter = THREE.LinearFilter;
				tex.magFilter = THREE.LinearFilter;
				loaded[i] = tex;
				textures.value = [...loaded];

				// Apply first texture as soon as it loads
				if (i === 0 && screenMatARef.value) {
					screenMatARef.value.map = tex;
					screenMatARef.value.needsUpdate = true;
				}
			},
			undefined,
			() => {
				loaded[i] = null;
			},
		);
	});
});

// --- Render loop (keeps TresJS rendering continuously) ---
const { onBeforeRender } = useLoop();
onBeforeRender(({ delta }) => {
	// Intentionally minimal — GSAP drives all animations.
	// This callback keeps the render loop alive.
});

// --- Step transitions ---
function computeMonitorY(camZ, yOffset) {
	const visibleHeight = 2 * Math.tan(fovRad / 2) * camZ;
	return -(visibleHeight / 2) + 1.6 + yOffset;
}

watch(
	() => props.activeStep,
	(index) => {
		const group = groupRef.value;
		const camera = cameraRef.value;
		if (!group || !camera || index < 0 || index >= SUB_STEPS.length) return;

		const target = SUB_STEPS[index];
		const targetCamZ = BASE_CAM_Z + target.camZ;
		const monitorY = computeMonitorY(targetCamZ, target.yOffset);

		// Rotation
		gsap.to(group.rotation, {
			y: target.rotY,
			z: target.rotZ,
			duration: 0.8,
			ease: "power3.inOut",
		});

		// Position (X + Y)
		gsap.to(group.position, {
			x: target.posX,
			y: monitorY,
			duration: 0.8,
			ease: "power3.inOut",
		});

		// Camera Z
		gsap.to(camera.position, {
			z: targetCamZ,
			duration: 0.8,
			ease: "power3.inOut",
		});

		// Crossfade screen textures
		const matA = screenMatARef.value;
		const matB = screenMatBRef.value;
		const tex = textures.value[index];

		if (prevStep !== index && tex && matA && matB) {
			matB.map = tex;
			matB.needsUpdate = true;
			matB.opacity = 0;

			gsap.to(matB, {
				opacity: 1,
				duration: 0.8,
				ease: "power2.inOut",
				onComplete() {
					matA.map = tex;
					matA.needsUpdate = true;
					matA.opacity = 1;
					matB.opacity = 0;
				},
			});

			gsap.to(matA, {
				opacity: 0,
				duration: 0.8,
				ease: "power2.inOut",
			});
		}

		prevStep = index;
	},
);
</script>

<template>
	<!-- Camera -->
	<TresPerspectiveCamera
		ref="cameraRef"
		:args="[FOV, 1, 0.1, 100]"
		:position="[0, 0, BASE_CAM_Z]"
	/>

	<!-- Lighting -->
	<TresAmbientLight :intensity="0.4" />
	<TresDirectionalLight :position="[2, 3, 5]" :intensity="0.8" />
	<TresDirectionalLight :position="[-3, -1, 3]" :intensity="0.15" color="#22d3ee" />

	<!-- Monitor group -->
	<TresGroup
		ref="groupRef"
		:rotation="[0, step0.rotY, step0.rotZ]"
		:position="[step0.posX, initialY, 0]"
	>
		<!-- Body (rounded box) -->
		<TresMesh>
			<primitive :object="bodyGeo" />
			<TresMeshPhysicalMaterial
				color="#111122"
				:roughness="0.22"
				:metalness="0.85"
				:clearcoat="0.3"
				:clearcoat-roughness="0.15"
			/>
		</TresMesh>

		<!-- Bezel inset -->
		<TresMesh :position="[0, 0, insetZ]">
			<primitive :object="insetGeo" />
			<TresMeshStandardMaterial color="#0a0a14" :roughness="0.9" :metalness="0.1" />
		</TresMesh>

		<!-- Screen A (primary) -->
		<TresMesh :position="[0, 0, screenAZ]">
			<primitive :object="screenGeoA" />
			<TresMeshBasicMaterial
				ref="screenMatARef"
				:tone-mapped="false"
				:transparent="true"
				:opacity="1"
			/>
		</TresMesh>

		<!-- Screen B (crossfade overlay) -->
		<TresMesh :position="[0, 0, screenBZ]">
			<primitive :object="screenGeoB" />
			<TresMeshBasicMaterial
				ref="screenMatBRef"
				:tone-mapped="false"
				:transparent="true"
				:opacity="0"
			/>
		</TresMesh>
	</TresGroup>
</template>
