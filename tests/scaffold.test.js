/**
 * Scaffold verification tests — run with `node tests/scaffold.test.js`
 *
 * Simple assertion-based tests to verify the project skeleton is intact.
 * No Jest dependency required.
 */

import { strict as assert } from 'node:assert';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(fileURLToPath(import.meta.url), '../..');

function read(file) {
  return readFileSync(path.join(root, file), 'utf-8');
}

function exists(file) {
  return existsSync(path.join(root, file));
}

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ❌ ${name}: ${e.message}`);
  }
}

console.log('\n📦 Scaffold verification\n');

test('package.json has correct name', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(pkg.name, 'agent-game-test');
  assert.equal(pkg.type, 'module');
});

test('vite config exists', () => {
  assert.ok(exists('vite.config.js'));
});

test('index.html exists at root', () => {
  assert.ok(exists('index.html'));
});

test('src/main.js entry point exists', () => {
  assert.ok(exists('src/main.js'));
});

test('src/snake.js exports SnakeGame', () => {
  const content = read('src/snake.js');
  assert.ok(content.includes('export class SnakeGame'));
});

test('src/pong.js exports PongGame', () => {
  const content = read('src/pong.js');
  assert.ok(content.includes('export class PongGame'));
});

test('src/game.js exports Game base class', () => {
  const content = read('src/game.js');
  assert.ok(content.includes('export class Game'));
});

test('.gitignore includes node_modules and dist', () => {
  const content = read('.gitignore');
  assert.ok(content.includes('node_modules/'));
  assert.ok(content.includes('dist/'));
});

test('CI workflows exist', () => {
  assert.ok(exists('.github/workflows/lint-and-test.yml'));
  assert.ok(exists('.github/workflows/deploy.yml'));
  assert.ok(exists('.github/workflows/opencode.yml'));
});

test('public/ directory exists', () => {
  assert.ok(exists('public'));
});

test('tests/ directory exists', () => {
  assert.ok(exists('tests'));
});

console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);

// Remove old test comment file if present
import { rmSync } from 'node:fs';
try { rmSync(path.join(root, '.hermes/tmp/opencode-prompt-227.txt'), { force: true }); } catch {}

process.exit(failed > 0 ? 1 : 0);
