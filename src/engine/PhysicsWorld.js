
import { SpatialHash } from './SpatialHash.js';
import * as THREE from 'three';

export class PhysicsWorld {
    constructor(boundsSize = 100, maxParticles = 5000) {
        this.boundsSize = boundsSize;
        this.dt = 0.016; // 60 FPS fixed step

        // Structure of Arrays (SoA) for performance
        // indices align with particle IDs
        this.maxParticles = maxParticles;
        this.count = 0;

        this.positions = new Float32Array(maxParticles * 3);
        this.velocities = new Float32Array(maxParticles * 3);
        this.radii = new Float32Array(maxParticles);
        this.types = new Uint8Array(maxParticles); // 0: water, 1: protein, 2: lipid, etc

        // Map particle ID -> Spatial Hash Key
        this.spatialKeys = new Array(maxParticles).fill(null);

        // Constraints: pairs of [p1, p2, distance]
        this.constraints = [];

        // Grid for collisions
        this.grid = new SpatialHash(boundsSize, 2.0); // Cell size 2.0 (approx protein size)

        // E. coli Geometry
        this.cellLength = 0; // Starts as sphere, grows to rod
    }

    addParticle(x, y, z, type, radius = 1.0) {
        if (this.count >= this.maxParticles) return -1;

        const id = this.count++;
        const i3 = id * 3;

        this.positions[i3] = x;
        this.positions[i3 + 1] = y;
        this.positions[i3 + 2] = z;

        this.velocities[i3] = (Math.random() - 0.5) * 0.1;
        this.velocities[i3 + 1] = (Math.random() - 0.5) * 0.1;
        this.velocities[i3 + 2] = (Math.random() - 0.5) * 0.1;

        this.radii[id] = radius;
        this.types[id] = type;

        const key = this.grid.insert(id, x, y, z);
        this.spatialKeys[id] = key;

        return id;
    }

    update() {
        for (let i = 0; i < this.count; i++) {
            const i3 = i * 3;

            // 1. Brownian Motion (Thermal noise)
            // Smaller particles move faster
            const noiseStrength = 0.05 / this.radii[i];
            this.velocities[i3] += (Math.random() - 0.5) * noiseStrength;
            this.velocities[i3 + 1] += (Math.random() - 0.5) * noiseStrength;
            this.velocities[i3 + 2] += (Math.random() - 0.5) * noiseStrength;

            // 2. Drag / Damping (Simulate viscosity of cytoplasm)
            this.velocities[i3] *= 0.95;
            this.velocities[i3 + 1] *= 0.95;
            this.velocities[i3 + 2] *= 0.95;

            // 3. Integrate Position
            let x = this.positions[i3] + this.velocities[i3];
            let y = this.positions[i3 + 1] + this.velocities[i3 + 1];
            let z = this.positions[i3 + 2] + this.velocities[i3 + 2];

            this.positions[i3 + 2] = z; // temp update for spatial hash

            // Note: We'll do final position update after constraints
        }

        this.resolveConstraints();

        // Second pass for boundary and hash update
        for (let i = 0; i < this.count; i++) {
            const i3 = i * 3;
            let x = this.positions[i3];
            let y = this.positions[i3 + 1];
            let z = this.positions[i3 + 2];

            // 4. Boundary Confinement (Capsule / Rod)
            // Capsule defined by radius 'r' and amino-axis segment from (-L/2, 0, 0) to (L/2, 0, 0)
            const r = this.boundsSize;
            const L = this.cellLength || 0;
            const halfL = L / 2;

            // Find closest point on segment to particle (x,y,z)
            // Segment is on X-axis from -halfL to +halfL
            const clampedX = Math.max(-halfL, Math.min(halfL, x));

            const dx = x - clampedX; // Vector from segment
            const dy = y;
            const dz = z;

            const dSq = dx * dx + dy * dy + dz * dz;

            if (dSq > r * r) {
                const d = Math.sqrt(dSq);
                // Normalized vector from closest point on segment
                const nx = dx / d;
                const ny = dy / d;
                const nz = dz / d;

                // Reflect velocity
                const dot = this.velocities[i3] * nx + this.velocities[i3 + 1] * ny + this.velocities[i3 + 2] * nz;

                if (dot > 0) {
                    this.velocities[i3] -= 2 * dot * nx;
                    this.velocities[i3 + 1] -= 2 * dot * ny;
                    this.velocities[i3 + 2] -= 2 * dot * nz;
                }

                // Push back inside
                const push = r - 0.1;
                this.positions[i3] = clampedX + nx * push;
                this.positions[i3 + 1] = ny * push;
                this.positions[i3 + 2] = nz * push;

                // Update local vars
                x = this.positions[i3];
                y = this.positions[i3 + 1];
                z = this.positions[i3 + 2];
            }

            this.positions[i3] = x;
            this.positions[i3 + 1] = y;
            this.positions[i3 + 2] = z;

            // 5. Update Spatial Hash
            const currentKey = this.spatialKeys[i];
            const keyCheck = this.grid.getKey(x, y, z);
            if (keyCheck !== currentKey) {
                this.grid.remove(i, currentKey);
                this.grid.insert(i, x, y, z);
                this.spatialKeys[i] = keyCheck;
            }
        }

        this.resolveCollisions();
    }

    addConstraint(p1, p2, dist) {
        this.constraints.push([p1, p2, dist]);
    }

    resolveConstraints() {
        // Simple relaxation (Verlet-like)
        for (let k = 0; k < 3; k++) { // iterations
            for (const [p1, p2, restDist] of this.constraints) {
                const i1 = p1 * 3;
                const i2 = p2 * 3;

                const dx = this.positions[i1] - this.positions[i2];
                const dy = this.positions[i1 + 1] - this.positions[i2 + 1];
                const dz = this.positions[i1 + 2] - this.positions[i2 + 2];

                const currentDist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 0.001;
                const diff = (currentDist - restDist) / currentDist;

                // Move each half way
                const scalar = diff * 0.5;
                const ox = dx * scalar;
                const oy = dy * scalar;
                const oz = dz * scalar;

                this.positions[i1] -= ox;
                this.positions[i1 + 1] -= oy;
                this.positions[i1 + 2] -= oz;

                this.positions[i2] += ox;
                this.positions[i2 + 1] += oy;
                this.positions[i2 + 2] += oz;

                // Note: We are directly modifying positions, effectively adding velocity.
                // In a proper Verlet, we'd update velocities too, but for overdamped bio-sim this is okay.
            }
        }
    }

    resolveCollisions() {
        // Simple hard-sphere collision
        // For each particle, check neighbors
        const tempVec = new THREE.Vector3();

        for (let i = 0; i < this.count; i++) {
            const i3 = i * 3;
            const x = this.positions[i3];
            const y = this.positions[i3 + 1];
            const z = this.positions[i3 + 2];
            const r = this.radii[i];

            const neighbors = this.grid.query(x, y, z);

            for (const otherId of neighbors) {
                if (i === otherId) continue;

                const j3 = otherId * 3;
                const dx = x - this.positions[j3];
                const dy = y - this.positions[j3 + 1];
                const dz = z - this.positions[j3 + 2];

                const distSq = dx * dx + dy * dy + dz * dz;
                const minDist = r + this.radii[otherId];

                if (distSq < minDist * minDist && distSq > 0) {
                    const dist = Math.sqrt(distSq);
                    const overlap = minDist - dist;

                    // Normalized direction
                    const nx = dx / dist;
                    const ny = dy / dist;
                    const nz = dz / dist;

                    // Separate particles (0.5 each)
                    const correction = overlap * 0.5;

                    this.positions[i3] += nx * correction;
                    this.positions[i3 + 1] += ny * correction;
                    this.positions[i3 + 2] += nz * correction;

                    this.positions[j3] -= nx * correction;
                    this.positions[j3 + 1] -= ny * correction;
                    this.positions[j3 + 2] -= nz * correction;

                    // Elastic bounce exchange (simplified)
                    // A proper impulse resolution would be better but expensive for thousands
                    // We just add a repulsion force to velocity
                    const repulsion = 0.05;
                    this.velocities[i3] += nx * repulsion;
                    this.velocities[i3 + 1] += ny * repulsion;
                    this.velocities[i3 + 2] += nz * repulsion;

                    this.velocities[j3] -= nx * repulsion;
                    this.velocities[j3 + 1] -= ny * repulsion;
                    this.velocities[j3 + 2] -= nz * repulsion;
                }
            }
        }
    }
}
