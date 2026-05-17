import { useEffect, useRef } from "react";

interface AuroraProps {
  className?: string;
  colorStops?: [string, string, string];
  amplitude?: number;
  blend?: number;
  speed?: number;
}

const VERT = /* glsl */ `
attribute vec2 position;
varying vec2 vUv;
void main() {
  vUv = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}
`;

const FRAG = /* glsl */ `
precision highp float;
varying vec2 vUv;
uniform float uTime;
uniform vec3 uColorA;
uniform vec3 uColorB;
uniform vec3 uColorC;
uniform float uAmplitude;
uniform float uBlend;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void main() {
  vec2 uv = vUv;
  float n = noise(vec2(uv.x * 2.6, uv.y * 1.6 + uTime * 0.06));
  float n2 = noise(vec2(uv.x * 1.2 - uTime * 0.05, uv.y * 2.2));
  float band = smoothstep(0.0, 1.0, uv.y + uAmplitude * (n - 0.5));
  float swirl = smoothstep(0.2, 0.85, n2 * 0.55 + 0.45 - uv.y * 0.4);

  vec3 col = mix(uColorA, uColorB, band);
  col = mix(col, uColorC, swirl * uBlend);

  // soft vignette on edges
  float vignette = smoothstep(1.0, 0.4, distance(uv, vec2(0.5)));
  col *= vignette;

  // overall lift
  gl_FragColor = vec4(col, 1.0);
}
`;

function hexToVec3(hex: string): [number, number, number] {
  const h = hex.replace("#", "");
  return [
    parseInt(h.slice(0, 2), 16) / 255,
    parseInt(h.slice(2, 4), 16) / 255,
    parseInt(h.slice(4, 6), 16) / 255,
  ];
}

export default function Aurora({
  className = "",
  colorStops = ["#0a0b09", "#8de8b9", "#f4ff78"],
  amplitude = 1.1,
  blend = 0.45,
  speed = 1,
}: AuroraProps) {
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const container = ref.current;
    if (!container) return;

    const prefersReduced =
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const canvas = document.createElement("canvas");
    canvas.style.display = "block";
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    container.appendChild(canvas);

    const gl = canvas.getContext("webgl", {
      antialias: true,
      alpha: true,
      premultipliedAlpha: false,
    });

    if (!gl) {
      container.style.background =
        "radial-gradient(circle at 80% 0%, " +
        colorStops[2] +
        "30, transparent 60%), radial-gradient(circle at 20% 90%, " +
        colorStops[1] +
        "30, transparent 60%), " +
        colorStops[0];
      return;
    }

    const compile = (type: number, source: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, source);
      gl.compileShader(s);
      return s;
    };
    const vs = compile(gl.VERTEX_SHADER, VERT);
    const fs = compile(gl.FRAGMENT_SHADER, FRAG);
    const program = gl.createProgram()!;
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.useProgram(program);

    const positionLoc = gl.getAttribLocation(program, "position");
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
      gl.STATIC_DRAW,
    );
    gl.enableVertexAttribArray(positionLoc);
    gl.vertexAttribPointer(positionLoc, 2, gl.FLOAT, false, 0, 0);

    const uTime = gl.getUniformLocation(program, "uTime");
    const uColorA = gl.getUniformLocation(program, "uColorA");
    const uColorB = gl.getUniformLocation(program, "uColorB");
    const uColorC = gl.getUniformLocation(program, "uColorC");
    const uAmplitude = gl.getUniformLocation(program, "uAmplitude");
    const uBlend = gl.getUniformLocation(program, "uBlend");

    gl.uniform3fv(uColorA, hexToVec3(colorStops[0]));
    gl.uniform3fv(uColorB, hexToVec3(colorStops[1]));
    gl.uniform3fv(uColorC, hexToVec3(colorStops[2]));
    gl.uniform1f(uAmplitude, amplitude);
    gl.uniform1f(uBlend, blend);

    const resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = container.clientWidth;
      const h = container.clientHeight;
      canvas.width = w * dpr;
      canvas.height = h * dpr;
      gl.viewport(0, 0, canvas.width, canvas.height);
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(container);

    let raf = 0;
    let start = performance.now();
    const tick = () => {
      const now = performance.now();
      const t = ((now - start) / 1000) * speed;
      gl.uniform1f(uTime, t);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      if (!prefersReduced) raf = requestAnimationFrame(tick);
    };
    if (prefersReduced) {
      gl.uniform1f(uTime, 4);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    } else {
      raf = requestAnimationFrame(tick);
    }

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      if (canvas.parentNode === container) container.removeChild(canvas);
    };
  }, [colorStops, amplitude, blend, speed]);

  return (
    <div
      ref={ref}
      aria-hidden
      className={"pointer-events-none absolute inset-0 " + className}
    />
  );
}
