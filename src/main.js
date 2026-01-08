
import './style.css'
import { PhysicsWorld } from './engine/PhysicsWorld.js';
import { CellRenderer } from './renderer/CellRenderer.js';
import { Chemistry } from './biology/Chemistry.js';
import { GPUNutrients } from './engine/GPUNutrients.js';

const app = document.querySelector('#app');
app.innerHTML = `
  <div style="position: absolute; top: 10px; left: 10px; color: white; pointer-events: none; user-select: none; z-index: 10; font-family: monospace;">
    <h1 style="margin: 0; font-size: 1.5em; text-shadow: 0 0 5px black;">E. coli Simulation</h1>
    <div style="background: rgba(0,0,0,0.5); padding: 10px; border-radius: 8px; margin-top: 10px;">
       <div>FPS: <span id="fps">0</span> | Particles: <span id="pcount">0</span></div>
       <div style="margin-top: 5px;">Time Speed: <span id="speed_val">1x</span></div>
       <input type="range" id="time_scale" min="0" max="5" step="0.1" value="1" style="pointer-events: auto;">
       
       <hr style="border: 0.5px solid #555; margin: 5px 0;">
       <div style="color: #ffff44">DNA: <span id="c_dna">0</span></div>
       <div style="color: #ff4444">Proteins: <span id="c_prot">0</span></div>
       <div style="color: #00ff00; margin-top: 5px;">Phase: <span id="cell_phase">G1 (Growth)</span></div>
       <button id="btn_rep" style="pointer-events: auto; margin-top: 5px;">Force Replication</button>
    </div>
  </div>
`;

async function main() {
  try {
    const world = new PhysicsWorld(50, 8000); // Radius 50
    const renderer = new CellRenderer();
    const chemistry = new Chemistry(world);

    // Custom colors
    const mats = renderer.instanceMgr.materials;
    mats[1].color.setHex(0xff4444); // Protein
    mats[3].color.setHex(0xffff44); // DNA
    mats[4].color.setHex(0xff00ff); // mRNA
    mats[10].color.setHex(0x00ff00); // Polymerase
    mats[20].color.setHex(0x00ffff); // Ribosome

    // DNA Setup
    let dnaIds = [];
    function createDNA(offsetX = 0) {
      let prevId = -1;
      const ids = [];
      const dnaLength = 200;
      let cx = offsetX, cy = 0, cz = 0;

      for (let i = 0; i < dnaLength; i++) {
        cx += (Math.random() - 0.5) * 2.0;
        cy += (Math.random() - 0.5) * 2.0;
        cz += (Math.random() - 0.5) * 2.0;

        // Constrain to center logic
        // (Simulate nucleoid)
        const centerDist = Math.sqrt((cx - offsetX) ** 2 + cy ** 2 + cz ** 2);
        if (centerDist > 15) {
          cx = (cx - offsetX) * 0.9 + offsetX;
          cy *= 0.9;
          cz *= 0.9;
        }

        const id = world.addParticle(cx, cy, cz, 3, 0.6);
        ids.push(id);
        if (prevId !== -1) {
          world.addConstraint(prevId, id, 0.8);
        }
        prevId = id;
      }
      return ids;
    }

    dnaIds = createDNA(0);

    // Initial Enzymes
    for (let i = 0; i < 25; i++) world.addParticle((Math.random() - 0.5) * 20, (Math.random() - 0.5) * 20, (Math.random() - 0.5) * 20, 10, 1.5);
    for (let i = 0; i < 50; i++) world.addParticle((Math.random() - 0.5) * 40, (Math.random() - 0.5) * 40, (Math.random() - 0.5) * 40, 20, 2.0);
    // Background
    for (let i = 0; i < 200; i++) world.addParticle((Math.random() - 0.5) * 60, (Math.random() - 0.5) * 60, (Math.random() - 0.5) * 60, 1, 0.8);

    // Simulation State
    let timeScale = 1.0;
    let cellLength = 0;
    let phase = 'G1'; // G1, S, G2

    // UI Controls
    const speedSlider = document.getElementById('time_scale');
    const speedVal = document.getElementById('speed_val');
    const btnRep = document.getElementById('btn_rep');
    const phaseEl = document.getElementById('cell_phase');

    speedSlider.oninput = (e) => {
      timeScale = parseFloat(e.target.value);
      speedVal.innerText = timeScale + 'x';
    };

    btnRep.onclick = () => {
      if (phase === 'G1') startReplication();
    };

    function startReplication() {
      if (phase !== 'G1') return;
      phase = 'S';
      phaseEl.innerText = "S (Replication)";
      phaseEl.style.color = "yellow";

      // Instant DNA duplication for now (Simulating completion)
      // Offset new DNA slightly
      const newIds = createDNA(5);
      dnaIds = [...dnaIds, ...newIds];

      // Start Elongation
      setTimeout(() => {
        phase = 'G2';
        phaseEl.innerText = "G2 (Elongation)";
        phaseEl.style.color = "cyan";
      }, 3000);
    }

    let lastTime = performance.now();
    let frames = 0;

    // GPGPU Nutrients (RTX 3060 Power)
    // 1,000,000 particles to fully utilize GPU
    const nutrientSystem = new GPUNutrients(renderer.renderer, renderer.scene, 1000000);

    const ui = {
      fps: document.getElementById('fps'),
      pcount: document.getElementById('pcount'),
      dna: document.getElementById('c_dna'),
      prot: document.getElementById('c_prot')
    };

    function loop() {
      try {
        // Time Steps
        const steps = Math.floor(timeScale);
        const remainder = timeScale - steps;

        for (let k = 0; k < steps; k++) {
          // Growth Logic
          if (phase === 'G2') {
            if (cellLength < 60) {
              cellLength += 0.05;
            } else {
              phase = 'M';
              phaseEl.innerText = "M (Ready to Divide)";
              phaseEl.style.color = "red";
            }
          }

          // Divide Logic (Phase M)
          if (phase === 'M' && timeScale > 0) {
            if (!window.septumTimer) window.septumTimer = 0;
            window.septumTimer++;

            if (window.septumTimer > 200) { // Delay
              cellLength = 0;
              phase = 'G1';
              phaseEl.innerText = "G1 (Growth)";
              phaseEl.style.color = "lime";

              // Cut DNA in half (Reset to first 200)
              dnaIds = dnaIds.slice(0, 200);

              // Visual Feedback (Zoom bounce)
              renderer.camera.position.z += 5;
              setTimeout(() => renderer.camera.position.z -= 5, 500);

              // Reset cycle
              ui.prot.innerText = "DIVIDED";
              chemistry.proteinCount = 0;
              window.septumTimer = 0;
            }
          }

          // Update Physics Params
          world.cellLength = cellLength;

          world.update();
          chemistry.update();
        }

        // Update GPGPU Nutrients
        nutrientSystem.update(performance.now() * 0.001, 50, cellLength);

        // Simulated Absorption
        chemistry.absorbGlucose(1.0 * timeScale);

        // Visual Update (Membrane)
        if (renderer.membrane.length !== cellLength) {
          // Re-init membrane if shape changed significantly
          // Optimization: Only do this every ~1 unit of growth
          if (Math.abs(renderer.membrane.length - cellLength) > 1.0) {
            // We need to dispose old mesh ?
            renderer.scene.remove(renderer.membrane.heads);
            renderer.scene.remove(renderer.membrane.tails);
            renderer.scene.remove(renderer.membrane.cellWall);

            // Re-create
            renderer.membrane = new renderer.membrane.constructor(renderer.scene, 50, cellLength);
          }
        }

        renderer.render(world); // Render matching last logic state

        // Stats
        frames++;
        const now = performance.now();
        if (now - lastTime > 500) {
          ui.fps.innerText = Math.round(frames * 2);
          ui.pcount.innerText = world.count;
          ui.dna.innerText = world.types.filter(t => t === 3).length; // inefficient but ok for demo
          ui.prot.innerHTML = `${chemistry.proteinCount} <span style="font-size:0.8em; color:#aaa">ATP: ${Math.round(chemistry.atp)}</span>`;

          // Trigger natural replication if proteins high enough
          if (phase === 'G1' && chemistry.proteinCount > 400 && timeScale > 0) {
            startReplication();
          }

          frames = 0;
          lastTime = now;
        }

        requestAnimationFrame(loop);
      } catch (err) {
        console.error(err);
      }
    }

    loop();

  } catch (e) {
    console.error("Init Error:", e);
  }
}

main();
