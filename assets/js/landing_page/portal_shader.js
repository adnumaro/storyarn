/**
 * GLSL shaders for the hero portal energy ring.
 * Fragment shader creates a procedural ring using SDF + FBM noise
 * for the swirling energy/flame effect.
 */

export const vertexShader = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

export const fragmentShader = /* glsl */ `
  precision highp float;

  uniform float uTime;
  uniform float uIntensity;
  uniform float uScale;
  uniform vec2 uResolution;
  uniform vec2 uPortalCenter;
  uniform float uPortalMaxWidth;

  varying vec2 vUv;

  // --- Simplex-style 2D noise ---
  vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

  float snoise(vec2 v) {
    const vec4 C = vec4(
      0.211324865405187,   // (3.0 - sqrt(3.0)) / 6.0
      0.366025403784439,   // 0.5 * (sqrt(3.0) - 1.0)
     -0.577350269189626,   // -1.0 + 2.0 * C.x
      0.024390243902439    // 1.0 / 41.0
    );
    vec2 i = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
  }

  // --- Fractal Brownian Motion ---
  float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 5; i++) {
      value += amplitude * snoise(p * frequency);
      frequency *= 2.0;
      amplitude *= 0.5;
    }
    return value;
  }

  void main() {
    float portalHalfWidth = max(uPortalMaxWidth * 0.5, 1.0);
    vec2 uv = (gl_FragCoord.xy - uPortalCenter) / portalHalfWidth;
    uv.y *= 1.08;

    // Apply scroll zoom
    uv /= uScale;

    // Keep the portal visually capped even when the canvas spans the full hero.
    float horizontalMask = 1.0 - smoothstep(0.88, 1.14, abs(uv.x));
    float verticalMask = 1.0 - smoothstep(1.02, 1.38, abs(uv.y));
    float portalMask = horizontalMask * verticalMask;

    float dist = length(uv);
    float angle = atan(uv.x, uv.y);

    // Ring parameters
    float ringRadius = 0.44;
    float ringWidth = 0.09;

    // Noise-based distortion of the ring edge
    float t = uTime * 0.4;
    float noiseDistort = fbm(vec2(angle * 2.0 + t, dist * 3.0 - t * 0.5)) * 0.06;
    float distortedDist = dist + noiseDistort;

    // Ring SDF with soft edges
    float ringDist = abs(distortedDist - ringRadius);
    float ring = smoothstep(ringWidth, 0.0, ringDist);

    // Inner glow (closer to ring = brighter)
    float innerGlow = smoothstep(ringWidth * 3.0, 0.0, ringDist) * 0.7;

    // Outer energy halo — wide, soft glow replaces post-processing bloom
    float outerHalo = smoothstep(ringWidth * 8.0, 0.0, ringDist) * 0.25;
    float farGlow = smoothstep(ringWidth * 16.0, 0.0, ringDist) * 0.08;

    // Swirling energy pattern on the ring
    float swirl = fbm(vec2(
      angle * 3.0 - t * 1.2,
      distortedDist * 8.0 + t * 0.3
    ));
    float energy = ring * (0.5 + swirl * 0.6);

    // Flame tendrils extending outward
    float flameNoise = fbm(vec2(
      angle * 5.0 + t * 0.8,
      dist * 4.0 - t * 0.6
    ));
    float flameMask = smoothstep(ringRadius + ringWidth * 4.0, ringRadius, dist);
    flameMask *= smoothstep(ringRadius - ringWidth * 0.5, ringRadius, dist);
    float flames = flameMask * max(flameNoise, 0.0) * 0.6;

    // Inward wisps (toward center)
    float inwardNoise = fbm(vec2(
      angle * 4.0 - t * 0.6,
      dist * 5.0 + t * 0.8
    ));
    float inwardMask = smoothstep(ringRadius - ringWidth * 3.0, ringRadius, dist);
    inwardMask *= smoothstep(ringRadius + ringWidth * 0.5, ringRadius, dist);
    float inwardWisps = inwardMask * max(inwardNoise, 0.0) * 0.35;

    // Flickering sparkle
    float sparkle = snoise(vec2(angle * 12.0 + t * 3.0, dist * 20.0));
    sparkle = pow(max(sparkle, 0.0), 4.0) * ring * 0.3;

    // Color palette
    vec3 teal      = vec3(0.031, 0.569, 0.698);
    vec3 cyan      = vec3(0.133, 0.827, 0.933);
    vec3 brightCyan = vec3(0.404, 0.910, 0.976);
    vec3 white     = vec3(0.85, 0.95, 1.0);

    // Color based on energy intensity
    float colorVal = energy + flames * 0.5 + sparkle;
    vec3 color = mix(teal, cyan, smoothstep(0.0, 0.3, colorVal));
    color = mix(color, brightCyan, smoothstep(0.3, 0.6, colorVal));
    color = mix(color, white, smoothstep(0.6, 1.0, colorVal));

    // Combine all layers
    float alpha = energy + innerGlow + outerHalo + farGlow + flames + inwardWisps + sparkle;
    alpha *= uIntensity;
    alpha *= portalMask;
    alpha = clamp(alpha, 0.0, 1.0);

    // Premultiply for additive blending on dark background
    gl_FragColor = vec4(color * alpha, alpha);
  }
`;
