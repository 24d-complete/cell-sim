
import * as THREE from 'three';

export class InstanceMgr {
    constructor(scene, maxParticles) {
        this.scene = scene;
        this.maxParticles = maxParticles;
        this.meshes = new Map(); // typeId -> InstancedMesh
        this.dummy = new THREE.Object3D();

        // Define geometries and materials for different types
        this.geometries = {
            0: new THREE.SphereGeometry(0.5, 8, 8), // Water
            1: new THREE.IcosahedronGeometry(1.0, 1), // Protein-like
            2: new THREE.SphereGeometry(1.0, 8, 8), // Lipid/Small molecule
            3: new THREE.CapsuleGeometry(0.5, 2, 4, 8), // DNA/RNA segment (simplified)
            4: new THREE.SphereGeometry(0.6, 8, 8), // mRNA
            10: new THREE.SphereGeometry(1.5, 16, 16), // Polymerase
            20: new THREE.SphereGeometry(2.0, 16, 16)  // Ribosome
        };

        this.materials = {
            0: new THREE.MeshStandardMaterial({ color: 0x44aa88 }),
            1: new THREE.MeshStandardMaterial({ color: 0xff4444 }),
            2: new THREE.MeshStandardMaterial({ color: 0x4444ff }),
            3: new THREE.MeshStandardMaterial({ color: 0xffff44 }),
            4: new THREE.MeshStandardMaterial({ color: 0xff00ff }), // mRNA
            10: new THREE.MeshStandardMaterial({ color: 0x00ff00 }), // Polymerase
            20: new THREE.MeshStandardMaterial({ color: 0x00ffff })  // Ribosome
        };
    }

    createMesh(typeId, count) {
        let geo = this.geometries[typeId] || new THREE.SphereGeometry(1, 8, 8);
        let mat = this.materials[typeId] || new THREE.MeshStandardMaterial({ color: 0xffffff });

        const mesh = new THREE.InstancedMesh(geo, mat, count);
        mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
        this.scene.add(mesh);
        this.meshes.set(typeId, mesh);

        return mesh;
    }

    update(physicsWorld) {
        // Group particles by type to batch update
        const typeCounts = new Map(); // typeId -> index

        for (let i = 0; i < physicsWorld.count; i++) {
            const type = physicsWorld.types[i];

            if (!this.meshes.has(type)) {
                this.createMesh(type, physicsWorld.maxParticles);
            }

            const mesh = this.meshes.get(type);

            if (!typeCounts.has(type)) typeCounts.set(type, 0);
            const idx = typeCounts.get(type);

            const i3 = i * 3;
            this.dummy.position.set(
                physicsWorld.positions[i3],
                physicsWorld.positions[i3 + 1],
                physicsWorld.positions[i3 + 2]
            );
            this.dummy.scale.setScalar(physicsWorld.radii[i]);
            this.dummy.updateMatrix();

            mesh.setMatrixAt(idx, this.dummy.matrix);

            typeCounts.set(type, idx + 1);
        }

        // Mark updates
        for (const [type, mesh] of this.meshes) {
            const count = typeCounts.get(type) || 0;
            mesh.count = count; // Only render active count
            mesh.instanceMatrix.needsUpdate = true;
        }
    }
}
