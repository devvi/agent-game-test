import { Game } from './game.js';

const GRID_SIZE = 20;
const TILE_COUNT = 20; // 20 × 20 grid

/**
 * Classic Snake game.
 */
export class SnakeGame extends Game {
  constructor(canvas) {
    super(canvas);
    this.cellSize = canvas.width / TILE_COUNT;
    this.dir = { x: 1, y: 0 };
    this.nextDir = { x: 1, y: 0 };
    this.snake = [];
    this.food = { x: 8, y: 10 };
    this.moveTimer = 0;
    this.moveInterval = 0.15; // seconds per tick
    this.ready = false;
  }

  reset() {
    super.reset();
    this.snake = [
      { x: 10, y: 10 },
      { x: 9, y: 10 },
      { x: 8, y: 10 },
    ];
    this.dir = { x: 1, y: 0 };
    this.nextDir = { x: 1, y: 0 };
    this.moveTimer = 0;
    this.ready = false;
    this._placeFood();
  }

  start() {
    this.reset();
    this.ready = true;
    super.start();
  }

  handleKey(key) {
    const k = key.toLowerCase();
    if (k === 'arrowup' || k === 'w') {
      if (this.dir.y !== 1) this.nextDir = { x: 0, y: -1 };
    } else if (k === 'arrowdown' || k === 's') {
      if (this.dir.y !== -1) this.nextDir = { x: 0, y: 1 };
    } else if (k === 'arrowleft' || k === 'a') {
      if (this.dir.x !== 1) this.nextDir = { x: -1, y: 0 };
    } else if (k === 'arrowright' || k === 'd') {
      if (this.dir.x !== -1) this.nextDir = { x: 1, y: 0 };
    }
  }

  update(dt) {
    if (!this.ready) return;

    this.moveTimer += dt;
    if (this.moveTimer < this.moveInterval) return;
    this.moveTimer -= this.moveInterval;

    this.dir = { ...this.nextDir };

    const head = this.snake[0];
    const newHead = {
      x: head.x + this.dir.x,
      y: head.y + this.dir.y,
    };

    // Wall wrap-around
    if (newHead.x < 0) newHead.x = TILE_COUNT - 1;
    if (newHead.x >= TILE_COUNT) newHead.x = 0;
    if (newHead.y < 0) newHead.y = TILE_COUNT - 1;
    if (newHead.y >= TILE_COUNT) newHead.y = 0;

    // Self-collision
    for (const seg of this.snake) {
      if (seg.x === newHead.x && seg.y === newHead.y) {
        this.ready = false;
        return; // game over
      }
    }

    this.snake.unshift(newHead);

    // Eat food
    if (newHead.x === this.food.x && newHead.y === this.food.y) {
      this.score += 10;
      this._placeFood();
    } else {
      this.snake.pop();
    }
  }

  render() {
    const { ctx, canvas } = this;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw grid
    ctx.strokeStyle = '#1a1a2e';
    ctx.lineWidth = 0.5;
    for (let x = 0; x < TILE_COUNT; x++) {
      for (let y = 0; y < TILE_COUNT; y++) {
        ctx.strokeRect(x * this.cellSize, y * this.cellSize, this.cellSize, this.cellSize);
      }
    }

    // Draw snake
    this.snake.forEach((seg, i) => {
      const alpha = 1 - i * 0.02;
      ctx.fillStyle = i === 0 ? '#4ecca3' : `rgba(78, 204, 163, ${Math.max(alpha, 0.3)})`;
      ctx.fillRect(seg.x * this.cellSize + 1, seg.y * this.cellSize + 1, this.cellSize - 2, this.cellSize - 2);
    });

    // Draw food
    ctx.fillStyle = '#e94560';
    ctx.beginPath();
    ctx.arc(
      this.food.x * this.cellSize + this.cellSize / 2,
      this.food.y * this.cellSize + this.cellSize / 2,
      this.cellSize / 2 - 2,
      0, Math.PI * 2
    );
    ctx.fill();

    // Game over overlay
    if (!this.ready) {
      ctx.fillStyle = 'rgba(0, 0, 0, 0.6)';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#e94560';
      ctx.font = '24px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Game Over', canvas.width / 2, canvas.height / 2 - 10);
      ctx.font = '14px sans-serif';
      ctx.fillStyle = '#e0e0e0';
      ctx.fillText('Press SPACE to restart', canvas.width / 2, canvas.height / 2 + 20);
    }
  }

  _placeFood() {
    const occupied = new Set(this.snake.map((s) => `${s.x},${s.y}`));
    let pos;
    do {
      pos = {
        x: Math.floor(Math.random() * TILE_COUNT),
        y: Math.floor(Math.random() * TILE_COUNT),
      };
    } while (occupied.has(`${pos.x},${pos.y}`));
    this.food = pos;
  }
}
