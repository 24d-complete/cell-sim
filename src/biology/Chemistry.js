
export class Chemistry {
    constructor(world) {
        this.world = world;
        // User data
        this.states = new Int32Array(world.maxParticles).fill(-1);
        this.timers = new Float32Array(world.maxParticles).fill(0);

        // Types
        this.TYPE_PROTEIN = 1;
        this.TYPE_LIPID = 2;
        this.TYPE_DNA = 3;
        this.TYPE_MRNA = 4;
        this.TYPE_POLYMERASE = 10;
        this.TYPE_RIBOSOME = 20;

        // Statistics
        this.proteinCount = 0;
        this.atp = 100; // Starting Energy

        // Replication State
        this.replicating = false;
        this.replicationProgress = 0;
    }

    absorbGlucose(amount) {
        this.atp += amount;
        if (this.atp > 1000) this.atp = 1000;
    }

    update() {
        const { count, types } = this.world;

        // Count proteins to trigger growth
        let pCount = 0;
        for (let i = 0; i < count; i++) {
            if (types[i] === this.TYPE_PROTEIN) pCount++;

            // Logic for Polymerase (Transcription)
            if (types[i] === this.TYPE_POLYMERASE) {
                this.updatePolymerase(i);
            }
            // Logic for Ribosome (Translation)
            else if (types[i] === this.TYPE_RIBOSOME) {
                this.updateRibosome(i);
            }
        }
        this.proteinCount = pCount;
    }

    updatePolymerase(id) {
        const state = this.states[id];

        if (state === -1) {
            const neighbors = this.getNeighbors(id);
            for (const otherId of neighbors) {
                if (this.world.types[otherId] === this.TYPE_DNA) {
                    if (Math.random() < 0.1) {
                        this.states[id] = otherId;
                        this.timers[id] = 0;
                        this.snapToParticle(id, otherId);
                    }
                    break;
                }
            }
        } else {
            const dnaId = state;
            this.snapToParticle(id, dnaId);

            this.timers[id] += 1.0; // Faster
            if (this.timers[id] > 50) {
                this.spawnMolecule(id, this.TYPE_MRNA);
                this.states[id] = -1;
            }
        }
    }

    updateRibosome(id) {
        const state = this.states[id];

        if (state === -1) {
            // Need ATP to start
            if (this.atp < 1) return;

            const neighbors = this.getNeighbors(id);
            for (const otherId of neighbors) {
                if (this.world.types[otherId] === this.TYPE_MRNA) {
                    if (Math.random() < 0.1) {
                        this.states[id] = otherId;
                        this.timers[id] = 0;
                        this.snapToParticle(id, otherId);
                    }
                    break;
                }
            }
        } else {
            const mrnaId = state;
            this.snapToParticle(id, mrnaId);

            this.timers[id] += 1.0;
            // Synthesis cost
            if (Math.random() < 0.1) this.atp -= 0.5;

            if (this.timers[id] > 40) {
                this.spawnMolecule(id, this.TYPE_PROTEIN);
                this.states[id] = -1;
            }
        }
    }

    getNeighbors(id) {
        const i3 = id * 3;
        const x = this.world.positions[i3];
        const y = this.world.positions[i3 + 1];
        const z = this.world.positions[i3 + 2];
        return this.world.grid.query(x, y, z);
    }

    snapToParticle(id, targetId) {
        const i3 = id * 3;
        const t3 = targetId * 3;
        this.world.positions[i3] = this.world.positions[t3] + 0.5;
        this.world.positions[i3 + 1] = this.world.positions[t3 + 1] + 0.5;
        this.world.positions[i3 + 2] = this.world.positions[t3 + 2];

        this.world.velocities[i3] = 0;
        this.world.velocities[i3 + 1] = 0;
        this.world.velocities[i3 + 2] = 0;
    }

    spawnMolecule(parentDt, type) {
        const i3 = parentDt * 3;
        const x = this.world.positions[i3];
        const y = this.world.positions[i3 + 1];
        const z = this.world.positions[i3 + 2];
        this.world.addParticle(x + 1, y + 1, z, type, 0.8);
    }
}
