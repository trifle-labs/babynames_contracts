#!/usr/bin/env node

/**
 * Generate a Merkle tree from SSA baby name data.
 *
 * Usage:
 *   cd script/merkle && npm install
 *   node generate-merkle-tree.mjs [path-to-names.zip]
 *
 * Default input: ~/Downloads/names.zip (SSA national data)
 * Outputs:
 *   ../../data/merkle-tree.json  — full tree dump for frontend (StandardMerkleTree.load())
 *   ../../data/merkle-root.txt   — bytes32 root for contract deployment
 *   ../../data/name-list.json    — flat array of all unique lowercased names
 */

import { readFileSync, writeFileSync, existsSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import AdmZip from "adm-zip";

const zipPath = process.argv[2] || resolve(homedir(), "Downloads/names.zip");

if (!existsSync(zipPath)) {
  console.error(`File not found: ${zipPath}`);
  console.error("Download from: https://www.ssa.gov/oact/babynames/names.zip");
  process.exit(1);
}

console.log(`Reading ${zipPath}...`);

const zip = new AdmZip(zipPath);
const entries = zip.getEntries();

// Find yob2024.txt (latest year)
const targetFile = "yob2024.txt";
const entry = entries.find((e) => e.entryName === targetFile);

if (!entry) {
  // Fall back to latest year available
  const yobFiles = entries
    .filter((e) => e.entryName.startsWith("yob") && e.entryName.endsWith(".txt"))
    .sort((a, b) => b.entryName.localeCompare(a.entryName));

  if (yobFiles.length === 0) {
    console.error("No yobNNNN.txt files found in zip");
    process.exit(1);
  }

  console.log(`yob2024.txt not found, using ${yobFiles[0].entryName}`);
  var data = yobFiles[0].getData().toString("utf8");
} else {
  var data = entry.getData().toString("utf8");
  console.log(`Using ${targetFile}`);
}

// Parse names: each line is "Name,Gender,Count"
const nameSet = new Set();
for (const line of data.split("\n")) {
  const trimmed = line.trim();
  if (!trimmed) continue;
  const [name] = trimmed.split(",");
  if (name) nameSet.add(name.toLowerCase());
}

const names = [...nameSet].sort();
console.log(`Found ${names.length} unique names`);

// Build merkle tree with leaf format: ['string'] encoding
// This matches: keccak256(bytes.concat(keccak256(abi.encode(name))))
const values = names.map((name) => [name]);
const tree = StandardMerkleTree.of(values, ["string"]);

console.log(`Merkle root: ${tree.root}`);

// Output paths
const dataDir = resolve(import.meta.dirname, "../../data");

// Full tree dump for frontend
writeFileSync(
  resolve(dataDir, "merkle-tree.json"),
  JSON.stringify(tree.dump(), null, 2)
);
console.log(`Wrote data/merkle-tree.json (${names.length} leaves)`);

// Root for contract
writeFileSync(resolve(dataDir, "merkle-root.txt"), tree.root + "\n");
console.log(`Wrote data/merkle-root.txt`);

// Flat name list for autocomplete
writeFileSync(
  resolve(dataDir, "name-list.json"),
  JSON.stringify(names)
);
console.log(`Wrote data/name-list.json`);

console.log("\nDone! Next steps:");
console.log("  1. Copy data/merkle-tree.json to babynames_market/public/data/");
console.log("  2. Deploy contract and run: forge script script/SetMerkleRoot.s.sol");
