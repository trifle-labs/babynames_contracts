#!/usr/bin/env node

/**
 * Generate historical SSA baby name data for the Name Explorer.
 *
 * Usage:
 *   cd script/merkle && npm install
 *   node generate-name-history.mjs [path-to-names.zip]
 *
 * Default input: ~/Downloads/names.zip (SSA national data)
 * Output:
 *   ../../data/name-history.json — structured JSON for frontend explorer
 */

import { writeFileSync, existsSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";
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

// Parse all yobYYYY.txt files
const yobFiles = entries
  .filter((e) => e.entryName.startsWith("yob") && e.entryName.endsWith(".txt"))
  .sort((a, b) => a.entryName.localeCompare(b.entryName));

if (yobFiles.length === 0) {
  console.error("No yobNNNN.txt files found in zip");
  process.exit(1);
}

console.log(`Found ${yobFiles.length} year files`);

// yearData[year][gender] = [{ name, count }, ...] sorted by count desc
const yearData = {};

for (const entry of yobFiles) {
  const year = parseInt(entry.entryName.replace("yob", "").replace(".txt", ""));
  const data = entry.getData().toString("utf8");

  yearData[year] = { M: [], F: [] };

  for (const line of data.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const [name, gender, countStr] = trimmed.split(",");
    const count = parseInt(countStr);
    if (name && gender && count) {
      yearData[year][gender].push({ name, count });
    }
  }

  // Already sorted by count in SSA data, but ensure it
  yearData[year].M.sort((a, b) => b.count - a.count);
  yearData[year].F.sort((a, b) => b.count - a.count);
}

const allYears = Object.keys(yearData).map(Number).sort((a, b) => a - b);
const minYear = allYears[0];
const maxYear = allYears[allYears.length - 1];
console.log(`Year range: ${minYear}-${maxYear}`);

// === 1. Recent rankings (2000-maxYear): top 200 per gender per year ===
const recentStartYear = 2000;
const recentYears = allYears.filter((y) => y >= recentStartYear);
const RECENT_TOP_N = 200;

const recentBoys = [];
const recentGirls = [];

for (const year of recentYears) {
  const boys = yearData[year].M.slice(0, RECENT_TOP_N);
  const girls = yearData[year].F.slice(0, RECENT_TOP_N);
  recentBoys.push({ names: boys.map((b) => b.name), counts: boys.map((b) => b.count) });
  recentGirls.push({ names: girls.map((g) => g.name), counts: girls.map((g) => g.count) });
}

console.log(`Recent: ${recentYears.length} years x top ${RECENT_TOP_N} per gender`);

// === 2. Historical decades (1880s-1990s): top 10 per gender per decade ===
const HISTORICAL_TOP_N = 10;
const decades = [];
const historicalBoys = [];
const historicalGirls = [];

for (let decade = 1880; decade <= 1990; decade += 10) {
  decades.push(decade);

  // Aggregate counts across the decade
  const boyCounts = {};
  const girlCounts = {};

  for (let y = decade; y < decade + 10 && y <= maxYear; y++) {
    if (!yearData[y]) continue;
    for (const { name, count } of yearData[y].M) {
      boyCounts[name] = (boyCounts[name] || 0) + count;
    }
    for (const { name, count } of yearData[y].F) {
      girlCounts[name] = (girlCounts[name] || 0) + count;
    }
  }

  const topBoys = Object.entries(boyCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, HISTORICAL_TOP_N);
  const topGirls = Object.entries(girlCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, HISTORICAL_TOP_N);

  historicalBoys.push({ names: topBoys.map(([n]) => n), counts: topBoys.map(([, c]) => c) });
  historicalGirls.push({ names: topGirls.map(([n]) => n), counts: topGirls.map(([, c]) => c) });
}

console.log(`Historical: ${decades.length} decades x top ${HISTORICAL_TOP_N} per gender`);

// === 3. Time series: top 25 all-time names per gender with rank every year ===
const TIMESERIES_TOP_N = 25;

// Find top 25 all-time by total count across all years
function getTopAllTime(gender) {
  const totalCounts = {};
  for (const year of allYears) {
    for (const { name, count } of yearData[year][gender]) {
      totalCounts[name] = (totalCounts[name] || 0) + count;
    }
  }
  return Object.entries(totalCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, TIMESERIES_TOP_N)
    .map(([name]) => name);
}

const topBoyNames = getTopAllTime("M");
const topGirlNames = getTopAllTime("F");

function buildTimeSeries(names, gender) {
  return names.map((name) => {
    const ranks = allYears.map((year) => {
      const idx = yearData[year][gender].findIndex((e) => e.name === name);
      return idx >= 0 ? idx + 1 : null;
    });
    return { name, ranks };
  });
}

const timeSeriesBoys = buildTimeSeries(topBoyNames, "M");
const timeSeriesGirls = buildTimeSeries(topGirlNames, "F");

console.log(`Time series: top ${TIMESERIES_TOP_N} per gender across ${allYears.length} years`);

// === 4. Search index: all names in top 1000 of any recent year, with year-by-year ranks ===
const SEARCH_TOP_N = 1000;

function buildSearchIndex(gender, genderKey) {
  // Collect all unique names that appear in top 1000 of any recent year
  const nameSet = new Set();
  for (const year of recentYears) {
    const entries = yearData[year][gender].slice(0, SEARCH_TOP_N);
    for (const { name } of entries) {
      nameSet.add(name);
    }
  }

  // For each name, store rank per recent year (null if outside top 1000)
  const index = [];
  for (const name of [...nameSet].sort()) {
    const ranks = recentYears.map((year) => {
      const idx = yearData[year][gender].findIndex((e) => e.name === name);
      return idx >= 0 && idx < SEARCH_TOP_N ? idx + 1 : null;
    });
    index.push({ name, ranks });
  }
  return index;
}

const searchBoys = buildSearchIndex("M", "boys");
const searchGirls = buildSearchIndex("F", "girls");

console.log(`Search index: ${searchBoys.length} boy names, ${searchGirls.length} girl names (top ${SEARCH_TOP_N})`);

// === Build output ===
const output = {
  generatedAt: new Date().toISOString(),
  yearRange: [minYear, maxYear],
  recent: {
    years: recentYears,
    boys: recentBoys,
    girls: recentGirls,
  },
  historical: {
    decades,
    boys: historicalBoys,
    girls: historicalGirls,
  },
  timeSeries: {
    years: allYears,
    boys: timeSeriesBoys,
    girls: timeSeriesGirls,
  },
  search: {
    years: recentYears,
    boys: searchBoys,
    girls: searchGirls,
  },
};

const jsonStr = JSON.stringify(output);
const dataDir = resolve(import.meta.dirname, "../../data");
const outPath = resolve(dataDir, "name-history.json");

writeFileSync(outPath, jsonStr);
const sizeKB = (Buffer.byteLength(jsonStr) / 1024).toFixed(1);
console.log(`\nWrote ${outPath} (${sizeKB} KB)`);

console.log("\nDone! Next steps:");
console.log("  cp data/name-history.json ../babynames_market/public/data/");
