import * as THREE from "three";

function getRandomInt(min, max) {
  return Math.floor(Math.random() * (max - min)) + min;
}

function getDegree(radian) {
  return (radian / Math.PI) * 180;
}

function getRadian(degrees) {
  return (degrees * Math.PI) / 180;
}

function getSpherical(rad1, rad2, r) {
  const x = Math.cos(rad1) * Math.cos(rad2) * r;
  const z = Math.cos(rad1) * Math.sin(rad2) * r;
  const y = Math.sin(rad1) * r;
  return new THREE.Vector3(x, y, z);
}

function initCamera(width, height) {
  let rad1_base = getRadian(0);
  let rad1 = rad1_base;
  let rad2 = getRadian(0);
  const range = 1000;
  const obj = new THREE.PerspectiveCamera(35, width / height, 1, 10000);
  obj.up.set(0, 1, 0);
  setPosition();
  lookAtCenter();

  function setPosition() {
    const points = getSpherical(rad1, rad2, range);
    obj.position.copy(points);
  }

  function lookAtCenter() {
    obj.lookAt(new THREE.Vector3(0, 0, 0));
  }

  function rotate() {
    rad1_base += getRadian(0.5);
    rad1 = getRadian(Math.sin(rad1_base) * 20 + 50);
    rad2 += getRadian(0.5);
    setPosition();
    lookAtCenter();
  }

  function resize(newWidth, newHeight) {
    obj.aspect = newWidth / newHeight;
    obj.updateProjectionMatrix();
  }

  return {
    obj,
    rotate,
    resize,
  };
}

function initHemiLight(hex1 = 0xffffff, hex2 = 0x333333) {
  const rad1 = getRadian(60);
  const rad2 = getRadian(30);
  const range = 1000;
  const intensity = 1;
  const obj = new THREE.HemisphereLight(hex1, hex2, intensity);
  setPosition();

  function setPosition() {
    const points = getSpherical(rad1, rad2, range);
    obj.position.copy(points);
  }

  return {
    obj,
  };
}

function debounce(object, eventType, callback) {
  let timer;

  object.addEventListener(
    eventType,
    function (event) {
      clearTimeout(timer);
      timer = setTimeout(() => {
        callback(event);
      }, 500);
    },
    false
  );
}

function friction(acceleration, mu, normal = 1, mass = 1) {
  const force = acceleration.clone();
  force.multiplyScalar(-1);
  force.normalize();
  force.multiplyScalar(mu);
  return force;
}

function drag(acceleration, value) {
  const force = acceleration.clone();
  force.multiplyScalar(-1);
  force.normalize();
  force.multiplyScalar(acceleration.length() * value);
  return force;
}

function hook(velocity, anchor, rest_length, k) {
  const force = velocity.clone().sub(anchor);
  const distance = force.length() - rest_length;
  force.normalize();
  force.multiplyScalar(-1 * k * distance);
  return force;
}

function initMover() {
  let position = new THREE.Vector3();
  let velocity = new THREE.Vector3();
  let acceleration = new THREE.Vector3();
  let anchor = new THREE.Vector3();
  const mass = 1;
  let isActive = false;

  function init(vector) {
    position = vector.clone();
    velocity = vector.clone();
    anchor = vector.clone();
    acceleration.set(0, 0, 0);
  }

  function updatePosition() {
    position.copy(velocity);
  }

  function updateVelocity() {
    acceleration.divideScalar(mass);
    velocity.add(acceleration);
  }

  function applyForce(vector) {
    acceleration.add(vector);
  }

  function applyFriction() {
    const frictionForce = friction(acceleration, 0.1);
    applyForce(frictionForce);
  }

  function applyDragForce(value) {
    const dragForce = drag(acceleration, value);
    applyForce(dragForce);
  }

  function applyHook(rest_length, k) {
    const hookForce = hook(velocity, anchor, rest_length, k);
    applyForce(hookForce);
  }

  function activate() {
    isActive = true;
  }

  function inactivate() {
    isActive = false;
  }

  return {
    init,
    updatePosition,
    updateVelocity,
    applyForce,
    applyFriction,
    applyDragForce,
    applyHook,
    activate,
    inactivate,
    get position() {
      return position;
    },
    get isActive() {
      return isActive;
    },
  };
}

function initPoints() {
  const moversNum = 100000;
  const movers = [];
  const positions = new Float32Array(moversNum * 3);
  const colors = new Float32Array(moversNum * 3);
  const gravity = new THREE.Vector3(0, -0.05, 0);
  let geometry = new THREE.BufferGeometry();
  let material = new THREE.PointsMaterial({
    color: 0xffffff,
    size: 20,
    transparent: true,
    opacity: 0.5,
    map: createTexture(),
    depthTest: false,
    blending: THREE.AdditiveBlending,
    vertexColors: new THREE.Color([1, 1, 1]),
  });
  const obj = new THREE.Points(geometry, material);

  for (let i = 0; i < moversNum; i++) {
    const mover = initMover();
    const color = new THREE.Color(`hsl(${getRandomInt(20, 240)}, 60%, 50%)`);

    mover.init(new THREE.Vector3(0, 0, 0));
    movers.push(mover);
    positions[i * 3 + 0] = mover.position.x;
    positions[i * 3 + 1] = mover.position.y;
    positions[i * 3 + 2] = mover.position.z;
    color.toArray(colors, i * 3);
  }
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));

  function update() {
    for (let i = 0; i < movers.length; i++) {
      const mover = movers[i];
      if (mover.isActive) {
        mover.applyForce(gravity);
        mover.updateVelocity();
        mover.updatePosition();
        if (mover.position.y < -1000) {
          mover.init(new THREE.Vector3(0, 0, 0));
          mover.inactivate();
        }
      }
      positions[i * 3 + 0] = mover.position.x;
      positions[i * 3 + 1] = mover.position.y;
      positions[i * 3 + 2] = mover.position.z;
    }
    geometry.attributes.position.needsUpdate = true;
  }

  function activateMover() {
    let count = 0;

    for (let i = 0; i < movers.length; i++) {
      const mover = movers[i];
      if (mover.isActive) continue;
      const rad1 = getRadian(
        (Math.log(getRandomInt(32, 128)) / Math.log(128)) * 90
      );
      // const rad2 = getRadian(getRandomInt(0, 24) * 15);

      // const rad1 = getRadian(Math.random() * 40 + 45);
      const rad2 = getRadian(Math.random() * 360);
      const force = getSpherical(rad1, rad2, 5);
      mover.activate();
      mover.init(new THREE.Vector3(0, 0, 0));
      mover.applyForce(force);
      count++;
      if (count >= 200) break;
    }
  }

  function createTexture() {
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    canvas.width = 200;
    canvas.height = 200;
    const grad = ctx.createRadialGradient(100, 100, 20, 100, 100, 100);
    grad.addColorStop(0.2, "rgba(255, 255, 255, 1)");
    grad.addColorStop(0.5, "rgba(255, 255, 255, 0.3)");
    grad.addColorStop(1.0, "rgba(255, 255, 255, 0)");
    ctx.fillStyle = grad;
    ctx.arc(100, 100, 100, 0, Math.PI / 180, true);
    ctx.fill();
    const texture = new THREE.Texture(canvas);
    texture.minFilter = THREE.NearestFilter;
    texture.needsUpdate = true;
    return texture;
  }

  return {
    obj,
    update,
    activateMover,
  };
}

function loadTexture(url) {
  return new Promise((resolve, reject) => {
    const loader = new THREE.TextureLoader();
    loader.load(url, resolve, undefined, reject);
  });
}
async function initTextures() {
  const urls = ["./f.png", "./a.png", "./m.png", "./e.png"];
  const textures = await Promise.all(urls.map(loadTexture));
  return textures;
}

function createLetterMesh(texture, width, height) {
  const geometry = new THREE.PlaneGeometry(width, height);
  const material = new THREE.MeshBasicMaterial({
    map: texture,
    transparent: true,
  });
  const mesh = new THREE.Mesh(geometry, material);
  return mesh;
}

function rotateToFaceCamera(object, camera) {
  const cameraPosition = new THREE.Vector3().setFromMatrixPosition(
    camera.matrixWorld
  );
  object.lookAt(cameraPosition);
}

async function initFame(scene, camera) {
  const textures = await initTextures();
  const dimensions = [
    { width: 123 / 4, height: 256 / 4 },
    { width: 178 / 4, height: 256 / 4 },
    { width: 223 / 4, height: 256 / 4 },
    { width: 128 / 4, height: 256 / 4 },
  ];

  const positions = [-75, -25, 35, 92];
  const letters = textures.map((texture, index) => {
    const { width, height } = dimensions[index];
    const mesh = createLetterMesh(texture, width, height);
    scene.add(mesh);
    mesh.position.set(positions[index], 0, 100);
    scene.add(mesh);
    return {
      mesh,
      offset: positions[index],
    };
  });

  const startTime = Date.now();
  const amplitude = 5;
  const frequency = 5.5;
  return {
    update() {
      const elapsedTime = (Date.now() - startTime) / 1000;
      const cameraMatrix = new THREE.Matrix4().copy(camera.matrixWorld);
      letters.forEach(({ mesh, offset }, index) => {
        mesh.quaternion.copy(camera.quaternion); // Make the letter always face the camera
        const yPosition = amplitude * Math.sin(frequency * elapsedTime + index);
        const letterPosition = new THREE.Vector3(
          offset,
          yPosition,
          -500
        ).applyMatrix4(cameraMatrix);
        mesh.position.copy(letterPosition);
      });
    },
  };
}

async function init() {
  let bodyWidth = window.innerWidth;
  let bodyHeight = window.innerHeight;
  let lastTimeActivate = Date.now();

  const canvas = document.getElementById("canvas");
  const renderer = new THREE.WebGLRenderer({
    antialias: true,
    canvas,
  });
  if (!renderer) {
    console.log("Failed to create renderer");
    return;
  }
  renderer.setSize(bodyWidth, bodyHeight);

  renderer.setClearColor(0x111111, 1.0);

  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0x000000, 0, 1600);

  const camera = initCamera(bodyWidth, bodyHeight);
  const fame = await initFame(scene, camera.obj);
  const light = initHemiLight(0xffff99, 0xffff99);
  const points = initPoints();

  scene.add(light.obj);
  scene.add(points.obj);

  function render() {
    renderer.clear();
    points.update();
    camera.rotate();

    fame.update();
    renderer.render(scene, camera.obj);
  }

  function renderLoop() {
    const now = Date.now();
    requestAnimationFrame(renderLoop);
    render();
    if (now - lastTimeActivate > 10) {
      points.activateMover();
      lastTimeActivate = Date.now();
    }
  }

  function resizeRenderer() {
    bodyWidth = window.innerWidth;
    bodyHeight = window.innerHeight;
    renderer.setSize(bodyWidth, bodyHeight);
    camera.resize(bodyWidth, bodyHeight);
  }

  debounce(window, "resize", resizeRenderer);
  renderLoop();
}

init();
