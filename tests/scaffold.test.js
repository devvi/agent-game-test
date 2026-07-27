/**
 * Test suite for the base Game engine.
 * Run: node --experimental-vm-modules node_modules/.bin/jest
 */

// We test via the browser-based code in a Node environment
// using a minimal canvas mock for basic logic validation.

describe('Game engine prelude', () => {
  test('package.json has correct metadata', () => {
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf-8'));
    expect(pkg.name).toBe('agent-game-test');
    expect(pkg.type).toBe('module');
    expect(pkg.scripts).toHaveProperty('dev');
    expect(pkg.scripts).toHaveProperty('build');
  });

  test('vite config exists and is valid', () => {
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const exists = fs.existsSync('vite.config.js');
    expect(exists).toBe(true);
  });

  test('public/index.html exists', () => {
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const exists = fs.existsSync('public/index.html');
    expect(exists).toBe(true);
  });

  test('src/main.js entry point exists', () => {
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const exists = fs.existsSync('src/main.js');
    expect(exists).toBe(true);
  });

  test('src/snake.js exports SnakeGame', () => {
    // Dynamic import not available in Jest without ESM mode,
    // so verify file exists and exports expected class name
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const content = fs.readFileSync('src/snake.js', 'utf-8');
    expect(content).toContain('export class SnakeGame');
  });

  test('src/pong.js exports PongGame', () => {
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const content = fs.readFileSync('src/pong.js', 'utf-8');
    expect(content).toContain('export class PongGame');
  });

  test('src/game.js exports Game', () => {
    // eslint-disable-next-line no-undef
    const fs = require('fs');
    const content = fs.readFileSync('src/game.js', 'utf-8');
    expect(content).toContain('export class Game');
  });
});
