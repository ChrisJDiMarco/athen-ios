/**
 * Downloads Philadelphia City Council district boundaries as GeoJSON.
 * Run once with: npm run fetch:districts
 * Source: OpenDataPhilly — Council Districts (2024).
 */
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SOURCE_URL =
  "https://opendata.arcgis.com/api/v3/datasets/9c50d54a4eea4eb0a9c2e8aabea1a5e0_0/downloads/data?format=geojson&spatialRefId=4326&where=1%3D1";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_PATH = resolve(__dirname, "..", "data", "philly-council-districts.geojson");

async function main() {
  console.log("Fetching Philadelphia council districts GeoJSON…");
  const res = await fetch(SOURCE_URL);
  if (!res.ok) {
    throw new Error(`Fetch failed: ${res.status} ${res.statusText}`);
  }
  const text = await res.text();

  const parsed = JSON.parse(text);
  if (parsed.type !== "FeatureCollection" || !Array.isArray(parsed.features)) {
    throw new Error("Downloaded file is not a valid GeoJSON FeatureCollection.");
  }

  await mkdir(dirname(OUT_PATH), { recursive: true });
  await writeFile(OUT_PATH, text, "utf8");
  console.log(`Wrote ${parsed.features.length} district features to ${OUT_PATH}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
