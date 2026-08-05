import { LAYERS } from "../model/edges.js";
import {
  createCamera,
  fitCamera,
  panCamera,
  sceneBounds,
  screenToWorld,
  visibleScene,
  worldToScreen,
  zoomAt,
} from "./camera.js";
import { SpatialIndex } from "./spatial-index.js";

function finite(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

const DELTA_COLORS = Object.freeze({
  added: "#83e6b4",
  increased: "#83e6b4",
  removed: "#ff8f83",
  decreased: "#ff8f83",
  unchanged: "#91aaa0",
});

function curveFor(edge, nodesById) {
  const source = nodesById.get(edge.source);
  const target = nodesById.get(edge.target);
  if (!source || !target) return null;
  const dx = target.x - source.x;
  const dy = target.y - source.y;
  const length = Math.hypot(dx, dy) || 1;
  const nx = -dy / length;
  const ny = dx / length;
  const bend = Math.min(70, length * .16) * ((hash(edge.id) & 1) ? 1 : -1);
  return {
    p0: source,
    p1: { x: source.x + dx * .5 + nx * bend, y: source.y + dy * .5 + ny * bend },
    p2: target,
  };
}

function hash(text) {
  let value = 0;
  for (let i = 0; i < String(text).length; i += 1) value = Math.imul(31, value) + String(text).charCodeAt(i) | 0;
  return value >>> 0;
}

function quadraticPoint(curve, t) {
  const u = 1 - t;
  return {
    x: u * u * curve.p0.x + 2 * u * t * curve.p1.x + t * t * curve.p2.x,
    y: u * u * curve.p0.y + 2 * u * t * curve.p1.y + t * t * curve.p2.y,
  };
}

function nodeColor(node) {
  if (node.groupColor) return node.groupColor;
  if (node.id === "government") return "#dc8d68";
  if (node.id === "bank") return "#aa8ce0";
  if (node.id === "central-bank") return "#77ace7";
  if (node.id === "outside-world" || node.id.startsWith("outside:")) return "#699bd0";
  if (node.id === "goods-market") return "#e6b65c";
  if (node.kind === "firm") return "#83e6b4";
  if (node.kind === "sector") return "#7fd8bd";
  if (node.id.includes("household") || node.id.startsWith("cohort:")) return "#78d6a9";
  return "#9bb9ad";
}

export function createCanvasRenderer(canvas, callbacks = {}) {
  const context = canvas.getContext("2d", { alpha: true, desynchronized: true });
  const camera = createCamera();
  const index = new SpatialIndex(120);
  const state = {
    scene: null,
    nodesById: new Map(),
    curves: [],
    bounds: null,
    scaleDomains: {},
    currentLayerMaxima: {},
    selection: null,
    hover: null,
    width: 1,
    height: 1,
    dpr: 1,
    dirty: true,
    frame: null,
    dragging: false,
    dragStart: null,
    moved: false,
    playing: false,
    reducedMotion: false,
    animationOrigin: performance.now(),
    reservedRight: 0,
    keyboardNodeIndex: -1,
    keyboardEdgeIndex: -1,
  };

  function resize() {
    const rect = canvas.getBoundingClientRect();
    const dpr = Math.max(1, Math.min(3, globalThis.devicePixelRatio || 1));
    state.width = Math.max(1, rect.width);
    state.height = Math.max(1, rect.height);
    state.dpr = dpr;
    const pixelWidth = Math.round(rect.width * dpr);
    const pixelHeight = Math.round(rect.height * dpr);
    if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
      canvas.width = pixelWidth;
      canvas.height = pixelHeight;
      markDirty();
    }
  }

  function viewport() {
    return { width: Math.max(1, state.width - state.reservedRight), height: state.height };
  }

  function rebuildIndex() {
    index.clear();
    for (const node of state.scene?.nodes || []) {
      const radius = node.radius + 6;
      index.insert({ type: "node", value: node }, { x: node.x - radius, y: node.y - radius, width: radius * 2, height: radius * 2 });
    }
  }

  function rebuildCurves() {
    state.nodesById = new Map((state.scene?.nodes || []).map((node) => [node.id, node]));
    state.curves = (state.scene?.edges || [])
      .map((edge) => ({ edge, curve: curveFor(edge, state.nodesById) }))
      .filter((item) => item.curve);
  }

  function setScene(scene, { fit = false, scaleDomains = {}, reducedMotion = false } = {}) {
    state.scene = scene;
    state.scaleDomains = scaleDomains;
    state.currentLayerMaxima = {};
    for (const edge of scene?.edges || []) {
      const scaleKey = edge.scaleDomainId || edge.layer;
      state.currentLayerMaxima[scaleKey] = Math.max(
        state.currentLayerMaxima[scaleKey] || 0,
        finite(edge.amount),
      );
    }
    state.reducedMotion = reducedMotion;
    state.keyboardNodeIndex = -1;
    state.keyboardEdgeIndex = -1;
    state.bounds = sceneBounds(scene?.nodes || [], scene?.mode === "ego" ? 45 : 80);
    rebuildIndex();
    rebuildCurves();
    resize();
    if (fit || !visibleScene(camera, state.bounds, viewport())) fitScene();
    markDirty();
  }

  function setReservedRight(pixels) {
    const next = Math.max(0, finite(pixels));
    if (Math.abs(next - state.reservedRight) < .5) return;
    state.reservedRight = next;
    if (state.scene) fitScene();
  }

  function fitScene() {
    if (!state.bounds) return;
    const pad = state.scene?.mode === "ego" ? 42 : 28;
    fitCamera(camera, state.bounds, viewport(), { padding: pad, maxScale: state.scene?.mode === "ego" ? 1.35 : 1.8 });
    callbacks.onCamera?.({ ...camera });
    markDirty();
  }

  function setSelection(selection) {
    state.selection = selection;
    markDirty();
  }

  function setPlaying(playing) {
    state.playing = Boolean(playing) && !state.reducedMotion;
    state.animationOrigin = performance.now();
    markDirty();
  }

  function markDirty() {
    state.dirty = true;
    if (!state.frame) state.frame = requestAnimationFrame(render);
  }

  function edgeWidth(edge) {
    const scaleKey = edge.scaleDomainId || edge.layer;
    const domain = state.scaleDomains?.[scaleKey] || state.scaleDomains?.[edge.layer];
    const maximum = Math.max(1e-12, finite(domain?.max) || state.currentLayerMaxima[scaleKey] || 1);
    return .65 + Math.sqrt(Math.max(0, edge.amount) / maximum) * 9.5;
  }

  function drawEdge(item, timestamp) {
    const { edge, curve } = item;
    const selected = state.selection?.id === edge.id;
    const hovered = state.hover?.id === edge.id;
    const color = DELTA_COLORS[edge.deltaClass] || LAYERS[edge.layer]?.color || "#83e6b4";
    const width = edgeWidth(edge);
    context.save();
    context.beginPath();
    context.moveTo(curve.p0.x, curve.p0.y);
    context.quadraticCurveTo(curve.p1.x, curve.p1.y, curve.p2.x, curve.p2.y);
    context.strokeStyle = color;
    context.globalAlpha = selected ? .98 : hovered ? .88 : Math.min(.72, .19 + width * .045);
    context.lineWidth = (selected ? width + 2 : width) / camera.scale;
    if (edge.nonCash) context.setLineDash([8 / camera.scale, 7 / camera.scale]);
    else if (edge.stockNonCash) context.setLineDash([2 / camera.scale, 5 / camera.scale]);
    else if (edge.deltaClass === "added") context.setLineDash([12 / camera.scale, 4 / camera.scale]);
    else if (edge.deltaClass === "removed") context.setLineDash([3 / camera.scale, 5 / camera.scale]);
    context.stroke();
    context.setLineDash([]);

    const arrowT = .78;
    const point = quadraticPoint(curve, arrowT);
    const ahead = quadraticPoint(curve, Math.min(.99, arrowT + .015));
    const angle = Math.atan2(ahead.y - point.y, ahead.x - point.x);
    const arrow = Math.max(5, Math.min(11, 4 + width * .65)) / camera.scale;
    context.translate(point.x, point.y);
    context.rotate(angle);
    context.beginPath();
    context.moveTo(arrow, 0);
    context.lineTo(-arrow * .7, arrow * .52);
    context.lineTo(-arrow * .7, -arrow * .52);
    context.closePath();
    context.fillStyle = color;
    context.globalAlpha = selected ? 1 : .83;
    context.fill();
    context.restore();

    if (state.playing && !edge.nonCash && width > 1.25) {
      const count = Math.min(3, Math.max(1, Math.round(width / 3.5)));
      for (let i = 0; i < count; i += 1) {
        const phase = ((timestamp - state.animationOrigin) / 2200 + i / count + (hash(edge.id) % 97) / 97) % 1;
        const particle = quadraticPoint(curve, phase);
        context.beginPath();
        context.arc(particle.x, particle.y, (1.5 + width * .12) / camera.scale, 0, Math.PI * 2);
        context.fillStyle = color;
        context.globalAlpha = .85;
        context.fill();
      }
    }
  }

  function drawNode(node) {
    const selected = state.selection?.id === node.id;
    const hovered = state.hover?.id === node.id;
    const color = nodeColor(node);
    const radius = Math.max(node.radius, (node.role === "focus" ? 9 : 6) / camera.scale);
    context.save();
    context.translate(node.x, node.y);
    context.beginPath();
    context.arc(0, 0, radius + (selected ? 5 / camera.scale : 0), 0, Math.PI * 2);
    context.fillStyle = color;
    context.globalAlpha = selected ? .22 : .1;
    context.fill();
    context.beginPath();
    context.arc(0, 0, radius, 0, Math.PI * 2);
    const gradient = context.createRadialGradient(-radius * .25, -radius * .32, radius * .08, 0, 0, radius);
    gradient.addColorStop(0, color);
    gradient.addColorStop(1, "#0a1a17");
    context.fillStyle = gradient;
    context.globalAlpha = 1;
    context.fill();
    context.strokeStyle = selected ? "#ddff9d" : hovered ? "#edf7f1" : color;
    context.lineWidth = (selected ? 2.6 : 1.25) / camera.scale;
    context.stroke();
    if (node.role === "focus") {
      context.beginPath();
      context.arc(0, 0, radius + 9 / camera.scale, 0, Math.PI * 2);
      context.strokeStyle = color;
      context.globalAlpha = .42;
      context.setLineDash([3 / camera.scale, 4 / camera.scale]);
      context.stroke();
    }
    context.restore();

    const showLabel = camera.scale > .82 || node.role === "focus" || node.role === "institution" || selected || hovered || state.scene?.mode === "economy" || state.scene?.mode === "ego";
    if (showLabel) {
      const fontSize = (node.role === "focus" ? 11 : 9.5) / camera.scale;
      context.save();
      context.font = `${node.role === "focus" ? 750 : 650} ${fontSize}px Inter, system-ui, sans-serif`;
      context.textAlign = "center";
      context.textBaseline = "top";
      context.lineWidth = 3.5 / camera.scale;
      context.strokeStyle = "rgba(3,10,9,.92)";
      const label = String(node.label || node.id);
      const short = label.length > 34 && node.role !== "focus" ? `${label.slice(0, 31)}…` : label;
      context.strokeText(short, node.x, node.y + radius + 5 / camera.scale);
      context.fillStyle = selected ? "#ddff9d" : "#dcece4";
      context.fillText(short, node.x, node.y + radius + 5 / camera.scale);
      context.restore();
    }
  }

  function drawGroupLabels() {
    const groups = new Map();
    for (const node of state.scene?.nodes || []) {
      if (!node.groupLabel) continue;
      const entry = groups.get(node.groupLabel) || { x: 0, y: 0, count: 0, color: node.groupColor };
      entry.x += node.x;
      entry.y += node.y;
      entry.count += 1;
      groups.set(node.groupLabel, entry);
    }
    context.save();
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.font = `${10 / camera.scale}px Inter, system-ui, sans-serif`;
    for (const [label, entry] of groups) {
      const x = entry.x / entry.count;
      const y = entry.y / entry.count;
      context.lineWidth = 4 / camera.scale;
      context.strokeStyle = "rgba(3,10,9,.94)";
      context.strokeText(label, x, y);
      context.fillStyle = entry.color || "#edf7f1";
      context.fillText(label, x, y);
    }
    context.restore();
  }

  function render(timestamp) {
    state.frame = null;
    resize();
    if (!state.dirty && !state.playing) return;
    state.dirty = false;
    context.setTransform(state.dpr, 0, 0, state.dpr, 0, 0);
    context.clearRect(0, 0, state.width, state.height);
    if (!state.scene) return;
    context.save();
    context.translate(camera.x, camera.y);
    context.scale(camera.scale, camera.scale);
    const sortedEdges = [...state.curves].sort((a, b) => edgeWidth(a.edge) - edgeWidth(b.edge));
    for (const item of sortedEdges) drawEdge(item, timestamp);
    drawGroupLabels();
    for (const node of state.scene.nodes) drawNode(node);
    context.restore();
    if (state.playing) state.frame = requestAnimationFrame(render);
  }

  function pointer(event) {
    const rect = canvas.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  function hitTest(screen) {
    const world = screenToWorld(camera, screen);
    const nodeCandidates = index.queryPoint(world.x, world.y);
    for (const candidate of nodeCandidates) {
      const node = candidate.value;
      if (Math.hypot(world.x - node.x, world.y - node.y) <= node.radius + 6 / camera.scale) return { type: "node", ...node };
    }
    const tolerance = 7 / camera.scale;
    let closest = null;
    let distance = Infinity;
    for (const item of state.curves) {
      for (let step = 1; step < 16; step += 1) {
        const point = quadraticPoint(item.curve, step / 16);
        const current = Math.hypot(world.x - point.x, world.y - point.y);
        if (current < distance && current <= tolerance + edgeWidth(item.edge) / camera.scale) {
          distance = current;
          closest = { type: "edge", ...item.edge };
        }
      }
    }
    return closest;
  }

  function cycleKeyboard(kind, backwards = false) {
    const items = kind === "node" ? state.scene?.nodes || [] : state.scene?.edges || [];
    if (!items.length) return false;
    const key = kind === "node" ? "keyboardNodeIndex" : "keyboardEdgeIndex";
    const step = backwards ? -1 : 1;
    state[key] = (state[key] + step + items.length) % items.length;
    const selection = { type: kind, ...items[state[key]] };
    state.hover = selection;
    callbacks.onHover?.(selection, { clientX: state.width / 2, clientY: state.height / 2 });
    callbacks.onSelect?.(selection);
    canvas.setAttribute("aria-label", `${kind === "node" ? "Actor" : "Relationship"} selected: ${selection.label || selection.id}. Press N for actors, R for relationships, Enter to reopen details, F to fit, or Escape to clear.`);
    markDirty();
    return true;
  }

  canvas.addEventListener("pointerdown", (event) => {
    canvas.setPointerCapture(event.pointerId);
    const point = pointer(event);
    state.dragging = true;
    state.dragStart = { point, cameraX: camera.x, cameraY: camera.y };
    state.moved = false;
    canvas.classList.add("dragging");
  });
  canvas.addEventListener("pointermove", (event) => {
    const point = pointer(event);
    if (state.dragging && state.dragStart) {
      const dx = point.x - state.dragStart.point.x;
      const dy = point.y - state.dragStart.point.y;
      if (Math.hypot(dx, dy) > 3) state.moved = true;
      camera.x = state.dragStart.cameraX + dx;
      camera.y = state.dragStart.cameraY + dy;
      callbacks.onCamera?.({ ...camera });
      markDirty();
      return;
    }
    const hit = hitTest(point);
    if (hit?.id !== state.hover?.id || hit?.type !== state.hover?.type) {
      state.hover = hit;
      canvas.classList.toggle("over-node", hit?.type === "node");
      canvas.classList.toggle("over-edge", hit?.type === "edge");
      callbacks.onHover?.(hit, { clientX: event.clientX, clientY: event.clientY });
      markDirty();
    }
  });
  canvas.addEventListener("pointerup", (event) => {
    const point = pointer(event);
    if (!state.moved) callbacks.onSelect?.(hitTest(point));
    state.dragging = false;
    state.dragStart = null;
    canvas.classList.remove("dragging");
    try { canvas.releasePointerCapture(event.pointerId); } catch { /* already released */ }
  });
  canvas.addEventListener("pointerleave", () => {
    if (!state.dragging) {
      state.hover = null;
      callbacks.onHover?.(null);
      markDirty();
    }
  });
  canvas.addEventListener("wheel", (event) => {
    event.preventDefault();
    zoomAt(camera, Math.exp(-event.deltaY * .0012), pointer(event));
    callbacks.onCamera?.({ ...camera });
    markDirty();
  }, { passive: false });
  canvas.addEventListener("keydown", (event) => {
    const step = event.shiftKey ? 80 : 35;
    if (event.key === "ArrowLeft") panCamera(camera, step, 0);
    else if (event.key === "ArrowRight") panCamera(camera, -step, 0);
    else if (event.key === "ArrowUp") panCamera(camera, 0, step);
    else if (event.key === "ArrowDown") panCamera(camera, 0, -step);
    else if (event.key === "+" || event.key === "=") zoomAt(camera, 1.2, { x: state.width / 2, y: state.height / 2 });
    else if (event.key === "-" || event.key === "_") zoomAt(camera, .82, { x: state.width / 2, y: state.height / 2 });
    else if (event.key.toLowerCase() === "f") fitScene();
    else if (event.key.toLowerCase() === "n") cycleKeyboard("node", event.shiftKey);
    else if (event.key.toLowerCase() === "r") cycleKeyboard("edge", event.shiftKey);
    else if (event.key === "Enter" && state.hover) callbacks.onSelect?.(state.hover);
    else if (event.key === "Escape") {
      state.hover = null;
      callbacks.onHover?.(null);
      callbacks.onSelect?.(null);
      canvas.setAttribute("aria-label", "Interactive economy map. Selection cleared. Press N to cycle actors, R to cycle relationships, F to fit, arrow keys to pan, plus or minus to zoom, and Escape to clear selection.");
    }
    else return;
    event.preventDefault();
    callbacks.onCamera?.({ ...camera });
    markDirty();
  });

  const resizeObserver = new ResizeObserver(() => {
    resize();
    if (state.bounds && !visibleScene(camera, state.bounds, viewport())) fitScene();
    markDirty();
  });
  resizeObserver.observe(canvas);
  canvas.setAttribute("aria-keyshortcuts", "N Shift+N R Shift+R Enter F Escape ArrowLeft ArrowRight ArrowUp ArrowDown + -");
  canvas.setAttribute("aria-label", "Interactive economy map. Press N to cycle actors, R to cycle relationships, F to fit, arrow keys to pan, plus or minus to zoom, and Escape to clear selection.");
  resize();

  return {
    setScene,
    setSelection,
    setPlaying,
    setReservedRight,
    fit: fitScene,
    zoom(factor) {
      zoomAt(camera, factor, { x: viewport().width / 2, y: viewport().height / 2 });
      callbacks.onCamera?.({ ...camera });
      markDirty();
    },
    getCamera: () => ({ ...camera }),
    getSceneBounds: () => state.bounds ? { ...state.bounds } : null,
    isSceneVisible: () => Boolean(state.bounds && visibleScene(camera, state.bounds, viewport())),
    destroy() {
      resizeObserver.disconnect();
      if (state.frame) cancelAnimationFrame(state.frame);
    },
  };
}
