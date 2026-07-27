import { Game } from './game.js';

const PADDLE_W = 10;
const PADDLE_H = 80;
const BALL_SIZE = 8;
const SPEED = 300;

/**
 * Classic Pong (1-player vs AI).
 */
export class PongGame extends Game {
  constructor(canvas) {
    super(canvas);
    this.paddleSpeed = 250;
    this.reset();
  }

  reset() {
    super.reset();
    this.playerY = this.canvas.height / 2 - PADDLE_H / 2;
    this.aiY = this.canvas.height / 2 - PADDLE_H / 2;
    this.ball = { x: this.canvas.width / 2, y: this.canvas.height / 2 };
    this.ballVx = SPEED * (Math.random() > 0.5 ? 1 : -1);
    this.ballVy = (Math.random() - 0.5) * SPEED * 0.5;
    this.ready = false;
  }

  start() {
    this.reset();
    this.ready = true;
    super.start();
  }

  handleKey(key) {
    const k = key.toLowerCase();
    if (k === 'arrowup') {
      this._up = true;
    } else if (k === 'arrowdown') {
      this._down = true;
    }
  }

  _clearKeys() {
    this._up = false;
    this._down = false;
  }

  update(dt) {
    if (!this.ready) return;
    const { width, height } = this.canvas;

    // Player paddle
    if (this._up) this.playerY -= this.paddleSpeed * dt;
    if (this._down) this.playerY += this.paddleSpeed * dt;
    this.playerY = Math.max(0, Math.min(height - PADDLE_H, this.playerY));
    this._clearKeys();

    // AI paddle
    const aiCenter = this.aiY + PADDLE_H / 2;
    if (this.ball.y < aiCenter - 10) this.aiY -= this.paddleSpeed * 0.7 * dt;
    if (this.ball.y > aiCenter + 10) this.aiY += this.paddleSpeed * 0.7 * dt;
    this.aiY = Math.max(0, Math.min(height - PADDLE_H, this.aiY));

    // Ball
    this.ball.x += this.ballVx * dt;
    this.ball.y += this.ballVy * dt;

    // Top/bottom bounce
    if (this.ball.y - BALL_SIZE / 2 < 0 || this.ball.y + BALL_SIZE / 2 > height) {
      this.ballVy *= -1;
    }

    // Player paddle collision
    if (
      this.ball.x - BALL_SIZE / 2 < PADDLE_W &&
      this.ball.x + BALL_SIZE / 2 > 0 &&
      this.ball.y > this.playerY &&
      this.ball.y < this.playerY + PADDLE_H
    ) {
      this.ballVx = Math.abs(this.ballVx) * 1.05;
      const offset = (this.ball.y - (this.playerY + PADDLE_H / 2)) / (PADDLE_H / 2);
      this.ballVy = offset * SPEED * 0.6;
      this.ball.x = PADDLE_W + BALL_SIZE / 2;
    }

    // AI paddle collision
    if (
      this.ball.x + BALL_SIZE / 2 > width - PADDLE_W &&
      this.ball.x - BALL_SIZE / 2 < width &&
      this.ball.y > this.aiY &&
      this.ball.y < this.aiY + PADDLE_H
    ) {
      this.ballVx = -Math.abs(this.ballVx) * 1.05;
      const offset = (this.ball.y - (this.aiY + PADDLE_H / 2)) / (PADDLE_H / 2);
      this.ballVy = offset * SPEED * 0.6;
      this.ball.x = width - PADDLE_W - BALL_SIZE / 2;
    }

    // Scoring / reset
    if (this.ball.x < -BALL_SIZE) {
      this.score = Math.max(0, this.score - 1);
      this._resetBall();
    } else if (this.ball.x > width + BALL_SIZE) {
      this.score += 1;
      this._resetBall();
    }
  }

  render() {
    const { ctx, canvas } = this;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Center line
    ctx.strokeStyle = '#0f3460';
    ctx.setLineDash([8, 8]);
    ctx.beginPath();
    ctx.moveTo(canvas.width / 2, 0);
    ctx.lineTo(canvas.width / 2, canvas.height);
    ctx.stroke();
    ctx.setLineDash([]);

    // Paddles
    ctx.fillStyle = '#e94560';
    ctx.fillRect(0, this.playerY, PADDLE_W, PADDLE_H);
    ctx.fillStyle = '#4ecca3';
    ctx.fillRect(canvas.width - PADDLE_W, this.aiY, PADDLE_W, PADDLE_H);

    // Ball
    ctx.fillStyle = '#e0e0e0';
    ctx.beginPath();
    ctx.arc(this.ball.x, this.ball.y, BALL_SIZE / 2, 0, Math.PI * 2);
    ctx.fill();
  }

  _resetBall() {
    this.ball.x = this.canvas.width / 2;
    this.ball.y = this.canvas.height / 2;
    this.ballVx = SPEED * (Math.random() > 0.5 ? 1 : -1);
    this.ballVy = (Math.random() - 0.5) * SPEED * 0.5;
  }
}
