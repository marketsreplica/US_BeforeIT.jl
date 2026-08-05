export function createCamera() {
  return { x: 0, y: 0, scale: 1, minScale: 0.08, maxScale: 4 };
}

export function sceneBounds(nodes, padding = 70) {
  if (!nodes?.length) return { x: -1, y: -1, width: 2, height: 2 };
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const node of nodes) {
    const radius = Number(node.radius) || 18;
    minX = Math.min(minX, node.x - radius);
    minY = Math.min(minY, node.y - radius);
    maxX = Math.max(maxX, node.x + radius);
    maxY = Math.max(maxY, node.y + radius);
  }
  return {
    x: minX - padding,
    y: minY - padding,
    width: Math.max(1, maxX - minX + padding * 2),
    height: Math.max(1, maxY - minY + padding * 2),
  };
}

export function fitCamera(camera, bounds, viewport, { padding = 28, maxScale = 2.2 } = {}) {
  const safeWidth = Math.max(1, viewport.width - padding * 2);
  const safeHeight = Math.max(1, viewport.height - padding * 2);
  const scale = Math.min(safeWidth / Math.max(1, bounds.width), safeHeight / Math.max(1, bounds.height), maxScale);
  camera.scale = Math.max(camera.minScale, Math.min(camera.maxScale, scale));
  camera.x = viewport.width / 2 - (bounds.x + bounds.width / 2) * camera.scale;
  camera.y = viewport.height / 2 - (bounds.y + bounds.height / 2) * camera.scale;
  return camera;
}

export function worldToScreen(camera, point) {
  return { x: point.x * camera.scale + camera.x, y: point.y * camera.scale + camera.y };
}

export function screenToWorld(camera, point) {
  return { x: (point.x - camera.x) / camera.scale, y: (point.y - camera.y) / camera.scale };
}

export function zoomAt(camera, factor, screenPoint) {
  const world = screenToWorld(camera, screenPoint);
  camera.scale = Math.max(camera.minScale, Math.min(camera.maxScale, camera.scale * factor));
  camera.x = screenPoint.x - world.x * camera.scale;
  camera.y = screenPoint.y - world.y * camera.scale;
  return camera;
}

export function panCamera(camera, dx, dy) {
  camera.x += dx;
  camera.y += dy;
  return camera;
}

export function visibleScene(camera, bounds, viewport, margin = 60) {
  const left = bounds.x * camera.scale + camera.x;
  const right = (bounds.x + bounds.width) * camera.scale + camera.x;
  const top = bounds.y * camera.scale + camera.y;
  const bottom = (bounds.y + bounds.height) * camera.scale + camera.y;
  return right >= -margin && left <= viewport.width + margin && bottom >= -margin && top <= viewport.height + margin;
}
