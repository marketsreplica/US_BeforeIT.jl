export class SpatialIndex {
  constructor(cellSize = 120) {
    this.cellSize = cellSize;
    this.cells = new Map();
  }

  clear() {
    this.cells.clear();
  }

  key(x, y) {
    return `${Math.floor(x / this.cellSize)}:${Math.floor(y / this.cellSize)}`;
  }

  insert(item, bounds) {
    const minX = Math.floor(bounds.x / this.cellSize);
    const maxX = Math.floor((bounds.x + bounds.width) / this.cellSize);
    const minY = Math.floor(bounds.y / this.cellSize);
    const maxY = Math.floor((bounds.y + bounds.height) / this.cellSize);
    for (let x = minX; x <= maxX; x += 1) {
      for (let y = minY; y <= maxY; y += 1) {
        const key = `${x}:${y}`;
        if (!this.cells.has(key)) this.cells.set(key, []);
        this.cells.get(key).push(item);
      }
    }
  }

  queryPoint(x, y) {
    return this.cells.get(this.key(x, y)) || [];
  }
}
