const path = require('path');
const fs = require('fs');
const BASE = __dirname;

// Helper to load .env file and return as object
function loadEnv(envPath) {
  const content = fs.readFileSync(envPath, 'utf8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIndex = trimmed.indexOf('=');
    if (eqIndex === -1) continue;
    const key = trimmed.substring(0, eqIndex).trim();
    let value = trimmed.substring(eqIndex + 1).trim();
    // Remove quotes if present
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

module.exports = {
  apps: [
    // 1. Base -> TON
    {
      name: 'bridge-base-to-ton',
      cwd: path.join(BASE, 'runs/1-bridge-base-to-ton'),
      script: 'node',
      args: '--require ts-node/register ../../apps/bridge/bridge.ts',
      env: loadEnv(path.join(BASE, 'runs/1-bridge-base-to-ton/.env')),
    },
    {
      name: 'watcher-base-to-ton-a',
      cwd: path.join(BASE, 'runs/1-watcher-base-to-ton-a'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-base-to-ton.ts',
      env: loadEnv(path.join(BASE, 'runs/1-watcher-base-to-ton-a/.env')),
    },
    {
      name: 'watcher-base-to-ton-b',
      cwd: path.join(BASE, 'runs/1-watcher-base-to-ton-b'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-base-to-ton.ts',
      env: loadEnv(path.join(BASE, 'runs/1-watcher-base-to-ton-b/.env')),
    },
    {
      name: 'watcher-base-to-ton-c',
      cwd: path.join(BASE, 'runs/1-watcher-base-to-ton-c'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-base-to-ton.ts',
      env: loadEnv(path.join(BASE, 'runs/1-watcher-base-to-ton-c/.env')),
    },

    // 2. BSC -> TON
    {
      name: 'bridge-bsc-to-ton',
      cwd: path.join(BASE, 'runs/2-bridge-bsc-to-ton'),
      script: 'node',
      args: '--require ts-node/register ../../apps/bridge/bridge.ts',
      env: loadEnv(path.join(BASE, 'runs/2-bridge-bsc-to-ton/.env')),
    },
    {
      name: 'watcher-bsc-to-ton-a',
      cwd: path.join(BASE, 'runs/2-watcher-bsc-to-ton-a'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-bsc-to-ton.ts',
      env: loadEnv(path.join(BASE, 'runs/2-watcher-bsc-to-ton-a/.env')),
    },
    {
      name: 'watcher-bsc-to-ton-b',
      cwd: path.join(BASE, 'runs/2-watcher-bsc-to-ton-b'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-bsc-to-ton.ts',
      env: loadEnv(path.join(BASE, 'runs/2-watcher-bsc-to-ton-b/.env')),
    },
    {
      name: 'watcher-bsc-to-ton-c',
      cwd: path.join(BASE, 'runs/2-watcher-bsc-to-ton-c'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-bsc-to-ton.ts',
      env: loadEnv(path.join(BASE, 'runs/2-watcher-bsc-to-ton-c/.env')),
    },

    // 3. TON -> Base
    {
      name: 'bridge-ton-to-base',
      cwd: path.join(BASE, 'runs/3-bridge-ton-to-base'),
      script: 'node',
      args: '--require ts-node/register ../../apps/bridge/bridge.ts',
      env: loadEnv(path.join(BASE, 'runs/3-bridge-ton-to-base/.env')),
    },
    {
      name: 'watcher-ton-to-base-a',
      cwd: path.join(BASE, 'runs/3-watcher-ton-to-base-a'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-ton-to-base.ts',
      env: loadEnv(path.join(BASE, 'runs/3-watcher-ton-to-base-a/.env')),
    },
    {
      name: 'watcher-ton-to-base-b',
      cwd: path.join(BASE, 'runs/3-watcher-ton-to-base-b'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-ton-to-base.ts',
      env: loadEnv(path.join(BASE, 'runs/3-watcher-ton-to-base-b/.env')),
    },
    {
      name: 'watcher-ton-to-base-c',
      cwd: path.join(BASE, 'runs/3-watcher-ton-to-base-c'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-ton-to-base.ts',
      env: loadEnv(path.join(BASE, 'runs/3-watcher-ton-to-base-c/.env')),
    },

    // 4. TON -> BSC
    {
      name: 'bridge-ton-to-bsc',
      cwd: path.join(BASE, 'runs/4-bridge-ton-to-bsc'),
      script: 'node',
      args: '--require ts-node/register ../../apps/bridge/bridge.ts',
      env: loadEnv(path.join(BASE, 'runs/4-bridge-ton-to-bsc/.env')),
    },
    {
      name: 'watcher-ton-to-bsc-a',
      cwd: path.join(BASE, 'runs/4-watcher-ton-to-bsc-a'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-ton-to-bsc.ts',
      env: loadEnv(path.join(BASE, 'runs/4-watcher-ton-to-bsc-a/.env')),
    },
    {
      name: 'watcher-ton-to-bsc-b',
      cwd: path.join(BASE, 'runs/4-watcher-ton-to-bsc-b'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-ton-to-bsc.ts',
      env: loadEnv(path.join(BASE, 'runs/4-watcher-ton-to-bsc-b/.env')),
    },
    {
      name: 'watcher-ton-to-bsc-c',
      cwd: path.join(BASE, 'runs/4-watcher-ton-to-bsc-c'),
      script: 'node',
      args: '--require ts-node/register ../../apps/watchers/watch-ton-to-bsc.ts',
      env: loadEnv(path.join(BASE, 'runs/4-watcher-ton-to-bsc-c/.env')),
    },
  ],
};
