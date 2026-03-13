#!/usr/bin/env ts-node
/**
 * Build script for TON Bridge Multisig contract
 * Compiles FunC source code to BoC format
 */

import { compileFunc } from '@ton-community/func-js';
import * as fs from 'fs';
import * as path from 'path';

const CONTRACTS_DIR = path.join(__dirname, '../contracts/ton');
const BUILD_DIR = path.join(__dirname, '../build');
const OUTPUT_FILE = path.join(BUILD_DIR, 'bridge-multisig.boc');

async function buildContract() {
  console.log('🔨 Building TON Bridge Multisig contract...\n');

  // Ensure build directory exists
  if (!fs.existsSync(BUILD_DIR)) {
    fs.mkdirSync(BUILD_DIR, { recursive: true });
  }

  // Read source files
  const mainSource = fs.readFileSync(
    path.join(CONTRACTS_DIR, 'bridge-multisig.fc'),
    'utf-8'
  );
  const stdlibSource = fs.readFileSync(
    path.join(CONTRACTS_DIR, 'stdlib.fc'),
    'utf-8'
  );

  console.log('✓ Source files loaded');

  // Compile
  const result = await compileFunc({
    targets: ['bridge-multisig.fc'],
    sources: {
      'bridge-multisig.fc': mainSource,
      'stdlib.fc': stdlibSource,
    },
  });

  if (result.status === 'error') {
    console.error('❌ Compilation failed:');
    console.error(result.message);
    process.exit(1);
  }

  console.log('✓ Compilation successful');

  // Write BoC file
  const bocBase64 = result.codeBoc;
  const bocBuffer = Buffer.from(bocBase64, 'base64');
  fs.writeFileSync(OUTPUT_FILE, new Uint8Array(bocBuffer));

  console.log(`✓ BoC file written to: ${OUTPUT_FILE}`);
  console.log(`  Size: ${bocBuffer.length} bytes`);
  console.log('\n✅ Build complete!');
}

buildContract().catch((error) => {
  console.error('❌ Build failed:', error);
  process.exit(1);
});
