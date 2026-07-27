/**
 * Base game engine — abstract class for snake & pong games.
 */
export class Game {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.running = false;
    this.paused = false;
    this.score = 0;
    this._raf = null;
    this._lastTime = 0;
  }

  /** Called once per frame. Override in subclass. */
  update(dt) {
    // subclass
  }

  /** Called every frame after update. Override in subclass. */
  render() {
    // subclass
  }

  /** Handle key events. Override in subclass. */
  handleKey(key) {
    // subclass
  }

  /** Kick off the game loop. */
  start() {
    if (this.running) return;
    this.running = true;
    this.paused = false;
    this._lastTime = performance.now();
    this._loop(this._lastTime);
  }

  /** Graceful stop. */
  stop() {
    this.running = false;
    if (this._raf) {
      cancelAnimationFrame(this._raf);
      this._raf = null;
    }
  }

  /** Toggle pause. */
  togglePause() {
    this.paused = !this.paused;
  }

  /** Reset to initial state. */
  reset() {
    this.score = 0;
    this.paused = false;
  }

  /* ---------- internal ---------- */

  _loop(now) {
    if (!this.running) return;
    const dt = Math.min((now - this._lastTime) / 1000, 0.05); // cap at 50 ms
    this._lastTime = now;

    if (!this.paused) {
      this.update(dt);
    }
    this.render();
    this._raf = requestAnimationFrame((t) => this._loop(t));
  }
}
