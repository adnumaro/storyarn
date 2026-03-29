<script setup>
/**
 * 3D monitor scene rendered inside a TresCanvas.
 * Displays rotating screenshots with GSAP-driven transitions.
 */
import { shallowRef, watch, onMounted } from "vue";
import { useLoop } from "@tresjs/core";
import * as THREE from "three";
import { gsap } from "gsap";
import { RoundedBoxGeometry } from 'three/addons'

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
	{ rotY: -0.4, rotZ: 0.02, posX: 0.6, posY: -0.2 },
	{ rotY: 0.4, rotZ: -0.02, posX: -0.6, posY: -0.2 },
	{ rotY: 0, rotZ: 0, posX: 0, posY: -0.3 },
];

const BASE_CAM_Z = 4.2;
const FOV = 40;

const groupRef = shallowRef(null);
const cameraRef = shallowRef(null);

const textures = shallowRef([]);
let prevStep = 0;
let stepTimeline = null;
let pendingTex = null; // texture that B is fading into

// --- Geometry & Materials ---
const screenW = 3.2;
const screenH = 2.0;
const bezelPad = 0.08;
const bezelW = screenW + bezelPad * 2;
const bezelH = screenH + bezelPad * 2;
const bodyDepth = 0.18;

const screenAZ = bodyDepth / 2 + 0.005;
const screenBZ = bodyDepth / 2 + 0.006;
const insetZ = bodyDepth / 2 + 0.003;

// Screen materials — imperative for direct texture control
const screenMatA = new THREE.MeshBasicMaterial({ transparent: true, opacity: 1, toneMapped: false });
const screenMatB = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, toneMapped: false });

// Pre-built screen meshes — avoids TresJS primitive-as-material issues
const screenMeshA = new THREE.Mesh(new THREE.PlaneGeometry(screenW, screenH), screenMatA);
screenMeshA.position.set(0, 0, screenAZ);

const screenMeshB = new THREE.Mesh(new THREE.PlaneGeometry(screenW, screenH), screenMatB);
screenMeshB.position.set(0, 0, screenBZ);

// Other geometry
const bodyGeo = new RoundedBoxGeometry(bezelW, bezelH, bodyDepth, 3, 0.04);
const insetGeo = new THREE.PlaneGeometry(screenW + 0.02, screenH + 0.02);

const step0 = SUB_STEPS[0];

// --- Texture loading + initial position ---
onMounted(() => {
	// Set initial position/rotation imperatively so TresJS template props
	// don't fight GSAP animations on re-render.
	const group = groupRef.value;
	if (group) {
		group.position.set(step0.posX, step0.posY, 0);
		group.rotation.set(0, step0.rotY, step0.rotZ);
	}

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

				if (i === 0) {
					screenMatA.map = tex;
					screenMatA.needsUpdate = true;
				}
			},
			undefined,
			() => {
				loaded[i] = null;
			},
		);
	});
});

// --- Render loop ---
const { onBeforeRender } = useLoop();
onBeforeRender(() => {});

// --- Step transitions ---
watch(
	() => props.activeStep,
	(index) => {
		const group = groupRef.value;
		const camera = cameraRef.value;
		if (!group || !camera || index < 0 || index >= SUB_STEPS.length) return;
		if (index === prevStep) return;

		// Kill ALL in-flight animations before starting new ones
		if (stepTimeline) {
			stepTimeline.kill();
			// Complete the interrupted swap: A should show what B was fading to
			if (pendingTex) {
				screenMatA.map = pendingTex;
				screenMatA.needsUpdate = true;
			}
			screenMatA.opacity = 1;
			screenMatB.opacity = 0;
			stepTimeline = null;
			pendingTex = null;
		}

		const target = SUB_STEPS[index];
		const tex = textures.value[index];
		const duration = 0.8;

		// Prepare crossfade: A is visible with current texture, B gets new texture
		if (tex) {
			pendingTex = tex;
			screenMatB.map = tex;
			screenMatB.needsUpdate = true;
			screenMatB.opacity = 0;
		}

		stepTimeline = gsap.timeline({
			onComplete() {
				if (tex) {
					screenMatA.map = tex;
					screenMatA.needsUpdate = true;
					screenMatA.opacity = 1;
					screenMatB.opacity = 0;
				}
				stepTimeline = null;
				pendingTex = null;
			},
		});

		// Position & rotation — all on the same timeline
		stepTimeline.to(group.rotation, { y: target.rotY, z: target.rotZ, duration, ease: "power3.inOut" }, 0);
		stepTimeline.to(group.position, { x: target.posX, y: target.posY, duration, ease: "power3.inOut" }, 0);

		// Texture crossfade
		if (tex) {
			stepTimeline.to(screenMatA, { opacity: 0, duration, ease: "power2.inOut" }, 0);
			stepTimeline.to(screenMatB, { opacity: 1, duration, ease: "power2.inOut" }, 0);
		}

		prevStep = index;
	},
);
</script>

<template>
	<TresPerspectiveCamera
		ref="cameraRef"
		:fov="FOV"
		:near="0.1"
		:far="100"
		:position="[0, 0, BASE_CAM_Z]"
	/>

	<TresAmbientLight :intensity="0.4" />
	<TresDirectionalLight :position="[2, 3, 5]" :intensity="0.8" />
	<TresDirectionalLight :position="[-3, -1, 3]" :intensity="0.15" color="#22d3ee" />

	<TresGroup
		ref="groupRef"
	>
		<!-- Body -->
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

		<!-- Screen A + B (pre-built meshes with imperative materials) -->
		<primitive :object="screenMeshA" />
		<primitive :object="screenMeshB" />
	</TresGroup>
</template>
