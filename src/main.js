import './style.css';
import { SnakeGame } from './snake.js';
import { PongGame } from './pong.js';

const canvas = document.getElementById('game-canvas');
const scoreDisplay = document.getElementById('score-display');
const statusDisplay = document.getElementById('status-display');

// Set canvas size
const SIZE = 400;
canvas.width = SIZE;
canvas.height = SIZE;

/* ---------- Game instances ---------- */
const snake = new SnakeGame(canvas);
const pong = new PongGame(canvas);
let current = snake;

/* ---------- UI helpers ---------- */
function updateUI() {
  scoreDisplay.textContent = `Score: ${current.score}`;
  statusDisplay.textContent = current.ready
    ? (current.paused ? 'Paused' : 'Playing — use arrow keys')
    : 'Game Over — press SPACE';
}

function switchGame(klass) {
  current.stop();
  if (klass === SnakeGame) {
    current = snake;
  } else {
    current = pong;
  }
  updateUI();
}

/* ---------- Tab buttons ---------- */
document.getElementById('btn-snake').addEventListener('click', () => {
  document.querySelectorAll('nav button').forEach((b) => b.classList.remove('active'));
  document.getElementById('btn-snake').classList.add('active');
  switchGame(SnakeGame);
});

document.getElementById('btn-pong').addEventListener('click', () => {
  document.querySelectorAll('nav button').forEach((b) => b.classList.remove('active'));
  document.getElementById('btn-pong').classList.add('active');
  switchGame(PongGame);
});

/* ---------- Keyboard ---------- */
window.addEventListener('keydown', (e) => {
  const key = e.key;
  if (key === ' ' || key === 'Spacebar') {
    e.preventDefault();
    if (!current.ready) {
      current.start();
      updateUI();
    } else if (key === ' ') {
      current.togglePause();
      updateUI();
    }
    return;
  }

  if (key === 'p' || key === 'P') {
    current.togglePause();
    updateUI();
    return;
  }

  // Route to current game
  current.handleKey(key);
});

/* ---------- Score polling ---------- */
setInterval(() => {
  if (current.running) updateUI();
}, 100);

/* ---------- Boot ---------- */
snake.start();
updateUI();
