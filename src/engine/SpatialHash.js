/**
 * specific implementation of a spatial hash grid for fixed-radius neighbor search.
 * Optimizes particle interactions by only checking nearby particles.
 */
export class SpatialHash {
  constructor(bounds, cellSize) {
    this.cellSize = cellSize;
    // Map of cellKey -> Set<particleId>
    // We use a Map and Sets for O(1) insertion/deletion
    this.cells = new Map();
  }

  /**
   * Convert 3D position to a unique string key
   */
  getKey(x, y, z) {
    const i = Math.floor(x / this.cellSize);
    const j = Math.floor(y / this.cellSize);
    const k = Math.floor(z / this.cellSize);
    return `${i},${j},${k}`;
  }

  /**
   * Generate keys for the cell containing the position and its 26 neighbors
   * @param {number} x
   * @param {number} y
   * @param {number} z
   * @returns {string[]} Array of keys
   */
  getNeighborKeys(x, y, z) {
    const keys = [];
    const i = Math.floor(x / this.cellSize);
    const j = Math.floor(y / this.cellSize);
    const k = Math.floor(z / this.cellSize);

    for (let di = -1; di <= 1; di++) {
      for (let dj = -1; dj <= 1; dj++) {
        for (let dk = -1; dk <= 1; dk++) {
          keys.push(`${i + di},${j + dj},${k + dk}`);
        }
      }
    }
    return keys;
  }

  insert(particleId, x, y, z) {
    const key = this.getKey(x, y, z);
    if (!this.cells.has(key)) {
      this.cells.set(key, new Set());
    }
    this.cells.get(key).add(particleId);
    return key; // Return key so we can track where the particle is
  }

  remove(particleId, key) {
    if (this.cells.has(key)) {
      const cell = this.cells.get(key);
      cell.delete(particleId);
      if (cell.size === 0) {
        this.cells.delete(key);
      }
    }
  }

  update(particleId, oldPos, newPos, currentKey) {
    const newKey = this.getKey(newPos.x, newPos.y, newPos.z);
    if (newKey !== currentKey) {
        this.remove(particleId, currentKey);
        this.insert(particleId, newPos.x, newPos.y, newPos.z);
        return newKey;
    }
    return currentKey;
  }

  query(x, y, z) {
    // Return all particles in the 27 particles around (x,y,z)
    const keys = this.getNeighborKeys(x, y, z);
    const neighbors = [];
    for (const key of keys) {
      if (this.cells.has(key)) {
        for (const pid of this.cells.get(key)) {
            neighbors.push(pid);
        }
      }
    }
    return neighbors;
  }
}
