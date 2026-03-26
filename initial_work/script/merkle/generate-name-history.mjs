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

import { writeFileSync, existsSync, mkdirSync } from "fs";
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

// === 1. Rankings (all years): top 200 per gender per year ===
const recentStartYear = minYear;
const recentYears = allYears;
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
  // Also compute all-time best rank/year across ALL years
  const index = [];
  for (const name of [...nameSet].sort()) {
    const ranks = recentYears.map((year) => {
      const idx = yearData[year][gender].findIndex((e) => e.name === name);
      return idx >= 0 && idx < SEARCH_TOP_N ? idx + 1 : null;
    });

    let bestRank = Infinity;
    let bestYear = allYears[0];
    for (const year of allYears) {
      const idx = yearData[year][gender].findIndex((e) => e.name === name);
      if (idx >= 0 && idx + 1 < bestRank) {
        bestRank = idx + 1;
        bestYear = year;
      }
    }

    index.push({ name, ranks, bestRank, bestYear });
  }
  return index;
}

const searchBoys = buildSearchIndex("M", "boys");
const searchGirls = buildSearchIndex("F", "girls");

console.log(`Search index: ${searchBoys.length} boy names, ${searchGirls.length} girl names (top ${SEARCH_TOP_N})`);

// === 5. All-names summary: every name that ever appeared, with best rank + current rank ===
// This lets search find ANY name, even if it's not in the top-1000 detailed index.
function buildAllNamesSummary(gender) {
  const searchNames = new Set(
    gender === "M" ? searchBoys.map((e) => e.name) : searchGirls.map((e) => e.name)
  );

  // For every name across all years, track best rank + year and latest rank
  const nameStats = {};

  for (const year of allYears) {
    const entries = yearData[year][gender];
    for (let i = 0; i < entries.length; i++) {
      const { name, count } = entries[i];
      if (searchNames.has(name)) continue; // already in detailed index

      const rank = i + 1;
      if (!nameStats[name]) {
        nameStats[name] = { best: rank, year, current: null, count: 0 };
      }
      if (rank < nameStats[name].best) {
        nameStats[name].best = rank;
        nameStats[name].year = year;
      }
      // Track latest year
      if (year === maxYear) {
        nameStats[name].current = rank;
        nameStats[name].count = count;
      }
    }
  }

  // Convert to sorted array (by best rank) — include names up to top 10000
  // (chunk data has ALL names, but the search summary caps here to keep initial load small)
  const ALL_NAMES_CUTOFF = 10000;
  return Object.entries(nameStats)
    .filter(([, s]) => s.best <= ALL_NAMES_CUTOFF)
    .map(([name, s]) => {
      const entry = { n: name, b: s.best, y: s.year };
      if (s.current !== null) {
        entry.c = s.current;
        entry.k = s.count;
      }
      return entry;
    })
    .sort((a, b) => a.b - b.b);
}

const allBoys = buildAllNamesSummary("M");
const allGirls = buildAllNamesSummary("F");

console.log(`All-names summary: ${allBoys.length} additional boy names, ${allGirls.length} additional girl names`);

const dataDir = resolve(import.meta.dirname, "../../data");

// === 6. Full historical ranks (sparse) for profile page ===
// For every name in the SSA data, store [year, rank] pairs across ALL years.
// No cutoff — includes every name that ever appeared (5+ births in a year).
// Sparse format: only years where the name appeared are stored.
// Chunked by first letter for on-demand loading (~0.1-1.9 MB per chunk).

function buildFullRanks(gender) {
  // Collect ALL names from the raw year data
  const nameSet = new Set();
  for (const year of allYears) {
    for (const { name } of yearData[year][gender]) {
      nameSet.add(name);
    }
  }

  const result = [];
  for (const name of [...nameSet].sort()) {
    const ranks = [];
    for (const year of allYears) {
      const idx = yearData[year][gender].findIndex((e) => e.name === name);
      if (idx >= 0) {
        ranks.push([year, idx + 1]);
      }
    }
    if (ranks.length > 0) {
      result.push([name, ranks]);
    }
  }
  return result;
}

const fullBoys = buildFullRanks("M");
const fullGirls = buildFullRanks("F");

const fullRanksOutput = {
  years: [minYear, maxYear],
  boys: fullBoys,
  girls: fullGirls,
};

const fullRanksJson = JSON.stringify(fullRanksOutput);
const fullRanksPath = resolve(dataDir, "name-ranks-full.json");
writeFileSync(fullRanksPath, fullRanksJson);
const fullSizeKB = (Buffer.byteLength(fullRanksJson) / 1024).toFixed(1);
console.log(`Full ranks: ${fullBoys.length} boy names, ${fullGirls.length} girl names (${fullSizeKB} KB)`);

// === 7. Trends-only ranks: names that ever appeared in top 25, for fast trends page load ===
const TRENDS_TOP_N = 25;

function buildTrendsRanks(gender) {
  // Find names that ever appeared in top TRENDS_TOP_N in any year
  const qualifyingNames = new Set();
  for (const year of allYears) {
    const entries = yearData[year][gender].slice(0, TRENDS_TOP_N);
    for (const { name } of entries) {
      qualifyingNames.add(name);
    }
  }

  // For qualifying names, store their full rank history (sparse, all ranks)
  const result = [];
  for (const name of [...qualifyingNames].sort()) {
    const ranks = [];
    for (const year of allYears) {
      const idx = yearData[year][gender].findIndex((e) => e.name === name);
      if (idx >= 0) {
        ranks.push([year, idx + 1]);
      }
    }
    if (ranks.length > 0) {
      result.push([name, ranks]);
    }
  }
  return result;
}

const trendsBoys = buildTrendsRanks("M");
const trendsGirls = buildTrendsRanks("F");

const trendsRanksOutput = {
  years: [minYear, maxYear],
  boys: trendsBoys,
  girls: trendsGirls,
};

const trendsRanksJson = JSON.stringify(trendsRanksOutput);
const trendsRanksPath = resolve(dataDir, "name-ranks-trends.json");
writeFileSync(trendsRanksPath, trendsRanksJson);
const trendsSizeKB = (Buffer.byteLength(trendsRanksJson) / 1024).toFixed(1);
console.log(`Trends ranks: ${trendsBoys.length} boy names, ${trendsGirls.length} girl names (${trendsSizeKB} KB)`);

// === 8. Chunked ranks by first letter + metadata for on-demand loading ===
// Split full ranks into per-letter chunks so the profile page only loads ~100-800 KB per name.
// Also generate meta.json with year range and yearMax per gender for unranked zone rendering.

function computeYearMax(fullEntries) {
  const yearMax = {};
  for (const [, sparseRanks] of fullEntries) {
    for (const [year, rank] of sparseRanks) {
      if (!yearMax[year] || rank > yearMax[year]) {
        yearMax[year] = rank;
      }
    }
  }
  return yearMax;
}

const boysYearMax = computeYearMax(fullBoys);
const girlsYearMax = computeYearMax(fullGirls);

const meta = {
  years: [minYear, maxYear],
  boys: boysYearMax,
  girls: girlsYearMax,
};

const chunksDir = resolve(dataDir, "name-ranks");
mkdirSync(resolve(chunksDir, "boys"), { recursive: true });
mkdirSync(resolve(chunksDir, "girls"), { recursive: true });

writeFileSync(resolve(chunksDir, "meta.json"), JSON.stringify(meta));
console.log(`Chunks meta: ${(Buffer.byteLength(JSON.stringify(meta)) / 1024).toFixed(1)} KB`);

function writeChunks(entries, genderDir, genderLabel) {
  // Group by first letter
  const byLetter = {};
  for (const entry of entries) {
    const letter = entry[0][0].toLowerCase();
    if (!byLetter[letter]) byLetter[letter] = [];
    byLetter[letter].push(entry);
  }

  let totalSize = 0;
  const letters = Object.keys(byLetter).sort();
  for (const letter of letters) {
    const json = JSON.stringify(byLetter[letter]);
    const path = resolve(chunksDir, genderDir, `${letter}.json`);
    writeFileSync(path, json);
    totalSize += Buffer.byteLength(json);
  }
  console.log(`Chunks ${genderLabel}: ${letters.length} files, ${(totalSize / 1024).toFixed(1)} KB total`);
}

writeChunks(fullBoys, "boys", "boys");
writeChunks(fullGirls, "girls", "girls");

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
  allNames: {
    boys: allBoys,
    girls: allGirls,
  },
};

const jsonStr = JSON.stringify(output);
const outPath = resolve(dataDir, "name-history.json");

writeFileSync(outPath, jsonStr);
const sizeKB = (Buffer.byteLength(jsonStr) / 1024).toFixed(1);
console.log(`\nWrote ${outPath} (${sizeKB} KB)`);

console.log("\nDone! Next steps:");
console.log("  cp data/name-history.json ../babynames_market/public/data/");
console.log("  cp data/name-ranks-trends.json ../babynames_market/public/data/");
console.log("  cp -r data/name-ranks ../babynames_market/public/data/");
