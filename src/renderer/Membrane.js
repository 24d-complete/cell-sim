
import * as THREE from 'three';

export class Membrane {
    constructor(scene, radius, length = 0) {
        this.scene = scene;
        this.radius = radius;
        this.length = length;
        this.count = 0;

        // Configuration
        this.lipidSize = 0.8;
        this.lipidSpacing = 1.0;

        // Area Calculation for Capsule
        // Cylinder Area: 2 * PI * r * L
        // Caps Area: 4 * PI * r^2
        const cylinderArea = 2 * Math.PI * radius * length;
        const capsArea = 4 * Math.PI * radius * radius;
        const totalArea = cylinderArea + capsArea;

        const particleCountEstimate = Math.floor(totalArea / (this.lipidSpacing * this.lipidSpacing));
        this.totalCount = particleCountEstimate * 2; // Bilayer

        console.log(`Generating Membrane: ${this.totalCount} Lipids`);

        this.initGeometry();
        this.initCellWall();
    }

    initCellWall() {
        // Transparent outer shell representing Peptidoglycan
        // Using a built-in Mesh for simplicity (not particles)
        const geo = new THREE.CapsuleGeometry(this.radius + 2, this.length, 4, 16);
        // Rotate to match X-axis alignment of physics (CapsuleGeo defaults to Y-axis)
        // We will rotate the mesh

        const mat = new THREE.MeshStandardMaterial({
            color: 0x44ff44, // Greenish
            transparent: true,
            opacity: 0.15,
            wireframe: true, // Grid-like structure
            side: THREE.DoubleSide
        });

        this.cellWall = new THREE.Mesh(geo, mat);
        this.cellWall.rotation.z = Math.PI / 2;
        this.scene.add(this.cellWall);
    }

    initGeometry() {
        // Lipids Geometry
        const headGeo = new THREE.SphereGeometry(this.lipidSize * 0.4, 5, 5);
        const headMat = new THREE.MeshStandardMaterial({ color: 0x88ccff, roughness: 0.3 });
        this.heads = new THREE.InstancedMesh(headGeo, headMat, this.totalCount);
        this.scene.add(this.heads);

        const tailGeo = new THREE.CapsuleGeometry(this.lipidSize * 0.1, this.lipidSize * 1.5, 4, 4);
        const tailMat = new THREE.MeshStandardMaterial({ color: 0xccccaa, roughness: 0.8 });
        this.tails = new THREE.InstancedMesh(tailGeo, tailMat, this.totalCount);
        this.scene.add(this.tails);

        const dummy = new THREE.Object3D();
        const dummyTail = new THREE.Object3D();

        const layerCount = Math.floor(this.totalCount / 2);

        // Distribution Strategy:
        // We can't use simple Fibonacci Sphere for a Capsule easily.
        // Simple approach: Monte Carlo Rejection Sampling on surface?
        // Or analytical mapping.

        // Let's use Monte Carlo for robustness regarding the shape.
        // Or simply: generate Fibonacci Sphere points, separate the halves, insert Cylinder points?

        // Better: Uniform Random distribution on surface.
        // Iterate until we fill layerCount.

        const r = this.radius;
        const L = this.length;
        const halfL = L / 2;

        // Helper to get random point on capsule surface (Outer)
        const getPointOnCapsule = (radius) => {
            // Randomly choose Cylinder or Caps based on area ratio
            const cylArea = 2 * Math.PI * radius * L;
            const capArea = 4 * Math.PI * radius * radius;
            const p = Math.random();
            const cylProb = cylArea / (cylArea + capArea);

            let pos = new THREE.Vector3();
            let normal = new THREE.Vector3();

            if (p < cylProb) {
                // Cylinder
                const theta = Math.random() * 2 * Math.PI;
                const x = (Math.random() - 0.5) * L;
                const y = Math.cos(theta) * radius;
                const z = Math.sin(theta) * radius;
                pos.set(x, y, z);
                normal.set(0, Math.cos(theta), Math.sin(theta));
            } else {
                // Caps
                // Random point on sphere
                const u = Math.random();
                const v = Math.random();
                const theta = 2 * Math.PI * u;
                const phi = Math.acos(2 * v - 1);

                const sx = Math.cos(phi) * radius;
                const sy = Math.sin(phi) * Math.sin(theta) * radius;
                const sz = Math.sin(phi) * Math.cos(theta) * radius;

                // Shift caps
                if (sx > 0) {
                    pos.set(sx + halfL, sy, sz);
                    normal.set(Math.cos(phi), Math.sin(phi) * Math.sin(theta), Math.sin(phi) * Math.cos(theta));
                } else {
                    pos.set(sx - halfL, sy, sz);
                    normal.set(Math.cos(phi), Math.sin(phi) * Math.sin(theta), Math.sin(phi) * Math.cos(theta));
                }
            }
            return { pos, normal };
        };

        // Outer Leaflet
        for (let i = 0; i < layerCount; i++) {
            const { pos, normal } = getPointOnCapsule(r);

            dummy.position.copy(pos);
            dummy.lookAt(0, 0, 0); // Reset rotation
            // Align to normal ?
            // Quat from (0,1,0) to normal
            // Simplified: just put mesh there.

            dummy.updateMatrix();
            this.heads.setMatrixAt(i, dummy.matrix);

            // Tail
            const tailPos = pos.clone().sub(normal.clone().multiplyScalar(0.6));
            dummyTail.position.copy(tailPos);
            // Rotate to align with normal
            const target = tailPos.clone().add(normal);
            dummyTail.lookAt(target);
            // Capsule geometry is Y-up. lookAt aligns Z to target.
            // We need to rotate X 90?
            dummyTail.rotateX(Math.PI / 2);

            dummyTail.updateMatrix();
            this.tails.setMatrixAt(i, dummyTail.matrix);
        }

        // Inner Leaflet
        const innerR = r - 2.0;
        for (let i = 0; i < layerCount; i++) {
            const idx = i + layerCount;
            const { pos, normal } = getPointOnCapsule(innerR);

            dummy.position.copy(pos);
            dummy.updateMatrix();
            this.heads.setMatrixAt(idx, dummy.matrix);

            // Tail pointing OUT
            const tailPos = pos.clone().add(normal.clone().multiplyScalar(0.6));
            dummyTail.position.copy(tailPos);
            const target = tailPos.clone().add(normal);
            dummyTail.lookAt(target);
            dummyTail.rotateX(Math.PI / 2);

            dummyTail.updateMatrix();
            this.tails.setMatrixAt(idx, dummyTail.matrix);
        }

        this.heads.instanceMatrix.needsUpdate = true;
        this.tails.instanceMatrix.needsUpdate = true;
    }
}
