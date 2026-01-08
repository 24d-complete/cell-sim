
import * as THREE from 'three';
import { GPUComputationRenderer } from 'three/examples/jsm/misc/GPUComputationRenderer.js';

export class GPUNutrients {
    constructor(renderer, scene, count = 50000) {
        this.renderer = renderer;
        this.scene = scene;
        this.count = count;

        // Dimensions for texture (sqrt of count)
        this.size = Math.ceil(Math.sqrt(count));
        this.count = this.size * this.size; // Adjust to square

        this.gpuCompute = new GPUComputationRenderer(this.size, this.size, renderer);

        if (renderer.capabilities.isWebGL2 === false) {
            this.gpuCompute.setDataType(THREE.HalfFloatType);
        }

        this.initCompute();
        this.initVisuals();
    }

    initCompute() {
        const dtPosition = this.gpuCompute.createTexture();
        const dtVelocity = this.gpuCompute.createTexture();

        this.fillTextures(dtPosition, dtVelocity);

        this.posVariable = this.gpuCompute.addVariable("texturePosition", this.computeShaderPosition(), dtPosition);
        this.velVariable = this.gpuCompute.addVariable("textureVelocity", this.computeShaderVelocity(), dtVelocity);

        this.gpuCompute.setVariableDependencies(this.posVariable, [this.posVariable, this.velVariable]);
        this.gpuCompute.setVariableDependencies(this.velVariable, [this.posVariable, this.velVariable]);

        // Uniforms for interaction
        this.posVariable.material.uniforms.time = { value: 0.0 };
        this.posVariable.material.uniforms.cellRadius = { value: 60.0 };
        this.posVariable.material.uniforms.cellLength = { value: 0.0 };

        this.velVariable.material.uniforms.time = { value: 0.0 };

        const error = this.gpuCompute.init();
        if (error !== null) {
            console.error("GPU Compute Error:", error);
        }
    }

    initVisuals() {
        // Render points based on Texture position
        const geometry = new THREE.BufferGeometry();

        const positions = new Float32Array(this.count * 3);
        const uvs = new Float32Array(this.count * 2);

        for (let i = 0; i < this.count; i++) {
            positions[i * 3] = 0;
            positions[i * 3 + 1] = 0;
            positions[i * 3 + 2] = 0; // Not used, shader uses texture

            const x = (i % this.size) / this.size;
            const y = Math.floor(i / this.size) / this.size;

            uvs[i * 2] = x;
            uvs[i * 2 + 1] = y;
        }

        geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        geometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));

        // Material that reads the computation texture
        this.material = new THREE.ShaderMaterial({
            uniforms: {
                texturePosition: { value: null },
                textureVelocity: { value: null }
            },
            vertexShader: `
                uniform sampler2D texturePosition;
                varying vec3 vColor;
                
                void main() {
                    vec4 posData = texture2D(texturePosition, uv);
                    vec3 pos = posData.xyz;
                    float life = posData.w; // w can be type/life
                    
                    // Simple size attenuation
                    vec4 mvPosition = modelViewMatrix * vec4(pos, 1.0);
                    gl_PointSize = (200.0 / -mvPosition.z); 
                    gl_Position = projectionMatrix * mvPosition;
                    
                    // Color based on location (Inside/Outside cell?)
                    // For now just white Nutrients
                    vColor = vec3(1.0, 1.0, 0.8);
                }
            `,
            fragmentShader: `
                varying vec3 vColor;
                void main() {
                    // Circular point
                    vec2 coord = gl_PointCoord - vec2(0.5);
                    if(length(coord) > 0.5) discard;
                    
                    gl_FragColor = vec4(vColor, 0.6);
                }
            `,
            transparent: true,
            depthWrite: false,
            blending: THREE.AdditiveBlending
        });

        this.mesh = new THREE.Points(geometry, this.material);
        this.mesh.frustumCulled = false; // Always render
        this.scene.add(this.mesh);
    }

    fillTextures(texturePos, textureVel) {
        const posArray = texturePos.image.data;
        const velArray = textureVel.image.data;

        for (let k = 0; k < posArray.length; k += 4) {
            // Random positions in a large box
            const r = 400;
            posArray[k + 0] = (Math.random() - 0.5) * r;
            posArray[k + 1] = (Math.random() - 0.5) * r;
            posArray[k + 2] = (Math.random() - 0.5) * r;
            posArray[k + 3] = 1; // Type

            velArray[k + 0] = (Math.random() - 0.5) * 0.5;
            velArray[k + 1] = (Math.random() - 0.5) * 0.5;
            velArray[k + 2] = (Math.random() - 0.5) * 0.5;
            velArray[k + 3] = 0;
        }
    }

    computeShaderPosition() {
        return `
            uniform float time;
            uniform float cellRadius;
            uniform float cellLength;

            void main() {
                vec2 uv = gl_FragCoord.xy / resolution.xy;
                vec4 tmpPos = texture2D(texturePosition, uv);
                vec4 tmpVel = texture2D(textureVelocity, uv);

                vec3 pos = tmpPos.xyz;
                vec3 vel = tmpVel.xyz;

                // Move
                pos += vel;

                // Wrap around (Toroidal world for infinite nutrients)
                float bounds = 200.0;
                if (pos.x > bounds) pos.x -= bounds * 2.0;
                if (pos.x < -bounds) pos.x += bounds * 2.0;
                if (pos.y > bounds) pos.y -= bounds * 2.0;
                if (pos.y < -bounds) pos.y += bounds * 2.0;
                if (pos.z > bounds) pos.z -= bounds * 2.0;
                if (pos.z < -bounds) pos.z += bounds * 2.0;

                gl_FragColor = vec4(pos, 1.0);
            }
        `;
    }

    computeShaderVelocity() {
        return `
            uniform float time;
            
            // simple pseudo-random
            float rand(vec2 co){
                return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
            }

            void main() {
                vec2 uv = gl_FragCoord.xy / resolution.xy;
                vec4 tmpVel = texture2D(textureVelocity, uv);
                vec3 vel = tmpVel.xyz;
                
                // Brownian Motion: Randomize velocity slightly
                vec3 noise = vec3(
                    rand(uv + time) - 0.5,
                    rand(uv + time + 1.1) - 0.5,
                    rand(uv + time + 2.2) - 0.5
                );
                
                vel += noise * 0.05; // Acceleration
                vel *= 0.98; // Drag
                
                gl_FragColor = vec4(vel, 1.0);
            }
        `;
    }

    update(time, cellRadius, cellLength) {
        this.posVariable.material.uniforms.time.value = time;
        this.posVariable.material.uniforms.cellRadius.value = cellRadius;
        this.posVariable.material.uniforms.cellLength.value = cellLength;

        this.velVariable.material.uniforms.time.value = time;

        this.gpuCompute.compute();

        // Update visuals with new positions
        this.material.uniforms.texturePosition.value = this.gpuCompute.getCurrentRenderTarget(this.posVariable).texture;
        this.material.uniforms.textureVelocity.value = this.gpuCompute.getCurrentRenderTarget(this.velVariable).texture;
    }
}
