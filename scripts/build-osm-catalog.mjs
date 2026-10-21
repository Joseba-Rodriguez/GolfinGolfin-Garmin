import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const MIN_TILE_LAT = 26;
const MAX_TILE_LAT = 45;
const MIN_TILE_LON = -20;
const MAX_TILE_LON = 6;

function normalizeFeatureId(feature) {
    const properties = feature?.properties ?? {};
    const raw = feature?.id ?? properties["@id"] ?? properties["@type_id"] ?? properties.osm_id;
    if (typeof raw === "string") {
        const match = raw.match(/^(node|way|relation)[/:](\d+)$/) ?? raw.match(/^([nwr])(\d+)$/);
        if (match) {
            const type = match[1] === "w" ? "way" : match[1] === "r" ? "relation" :
                match[1] === "n" ? "node" : match[1];
            return { type, id: Number(match[2]) };
        }
    }
    if (Number.isSafeInteger(raw) && raw > 0) {
        const type = properties["@type"];
        if (type === "way" || type === "relation" || type === "node") {
            return { type, id: raw };
        }
    }
    return null;
}

function featureTags(properties) {
    if (properties.tags && typeof properties.tags === "object") {
        return properties.tags;
    }
    const tags = {};
    for (const [key, value] of Object.entries(properties)) {
        if (!key.startsWith("@") && key !== "osm_id" && typeof value === "string") {
            tags[key] = value;
        }
    }
    return tags;
}

function coordinatesOf(geometry) {
    if (!geometry || !Array.isArray(geometry.coordinates)) {
        return [];
    }
    if (geometry.type === "LineString") {
        return geometry.coordinates;
    }
    if (geometry.type === "MultiLineString") {
        return geometry.coordinates.reduce((longest, line) =>
            line.length > longest.length ? line : longest, []);
    }
    return [];
}

function validCoordinate(point) {
    return Array.isArray(point) && Number.isFinite(point[0]) && Number.isFinite(point[1]) &&
        point[0] >= -180 && point[0] <= 180 && point[1] >= -90 && point[1] <= 90;
}

function polygonRings(geometry) {
    if (geometry?.type === "Polygon") {
        return [geometry.coordinates];
    }
    if (geometry?.type === "MultiPolygon") {
        return geometry.coordinates;
    }
    if (geometry?.type === "LineString" && geometry.coordinates.length >= 4) {
        const first = geometry.coordinates[0];
        const last = geometry.coordinates[geometry.coordinates.length - 1];
        if (first[0] === last[0] && first[1] === last[1]) {
            return [[geometry.coordinates]];
        }
    }
    return [];
}

function ringContains(ring, point) {
    let inside = false;
    for (let index = 0, previous = ring.length - 1; index < ring.length; previous = index++) {
        const [x1, y1] = ring[index];
        const [x2, y2] = ring[previous];
        if ((y1 > point[1]) !== (y2 > point[1]) &&
            point[0] < ((x2 - x1) * (point[1] - y1)) / (y2 - y1) + x1) {
            inside = !inside;
        }
    }
    return inside;
}

function geometryContains(geometry, point) {
    return polygonRings(geometry).some((polygon) => {
        if (!polygon.length || !ringContains(polygon[0], point)) {
            return false;
        }
        return !polygon.slice(1).some((hole) => ringContains(hole, point));
    });
}

function courseBounds(geometry) {
    const points = polygonRings(geometry).flat(2).filter(validCoordinate);
    if (!points.length) {
        return null;
    }
    const lons = points.map((point) => point[0]);
    const lats = points.map((point) => point[1]);
    const minLon = Math.min(...lons);
    const maxLon = Math.max(...lons);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    return {
        minLon,
        maxLon,
        minLat,
        maxLat,
        area: (maxLon - minLon) * (maxLat - minLat),
        center: [(minLon + maxLon) / 2, (minLat + maxLat) / 2]
    };
}

function parsePar(value) {
    if (typeof value !== "string" || !/^[3-6]$/.test(value)) {
        return null;
    }
    return value;
}

function courseRoundCount(tags, mappedHoleCount) {
    if (tags["golf:course"] === "9_hole") {
        return 9;
    }
    if (tags["golf:course"] === "18_hole") {
        return 18;
    }
    return mappedHoleCount === 9 ? 9 : 18;
}

function tileName(lat, lon) {
    return `lat_${lat}_lon_${lon}.json`;
}

export function buildCatalog(features, generatedAt = new Date().toISOString()) {
    const courses = [];
    const holes = [];

    for (const feature of features) {
        const properties = feature?.properties ?? {};
        const tags = featureTags(properties);
        const osm = normalizeFeatureId(feature);
        if (!osm) {
            continue;
        }
        if (tags.leisure === "golf_course" && typeof tags.name === "string" &&
            tags.name.trim() && (osm.type === "way" || osm.type === "relation")) {
            const bounds = courseBounds(feature.geometry);
            if (!bounds) {
                continue;
            }
            const course = {
                id: `${osm.type}/${osm.id}`,
                type: osm.type,
                osmId: osm.id,
                name: tags.name.trim().slice(0, 64),
                roundCount: courseRoundCount(tags, 0),
                center: bounds.center,
                bounds,
                geometry: feature.geometry,
                tags,
                holes: new Map()
            };
            courses.push(course);
        } else if (tags.golf === "hole" && osm.type === "way") {
            const coordinates = coordinatesOf(feature.geometry).filter(validCoordinate);
            if (coordinates.length >= 2) {
                holes.push({
                    id: osm.id,
                    tags,
                    coordinates,
                    target: coordinates[coordinates.length - 1],
                    length: coordinates.reduce((sum, point, index) => index === 0 ? sum :
                        sum + Math.hypot(point[0] - coordinates[index - 1][0],
                            point[1] - coordinates[index - 1][1]), 0)
                });
            }
        }
    }

    for (const hole of holes) {
        const candidates = courses.filter((course) => geometryContains(course.geometry, hole.target));
        if (!candidates.length) {
            continue;
        }
        candidates.sort((left, right) => left.bounds.area - right.bounds.area);
        const course = candidates[0];
        const reference = hole.tags.ref;
        if (typeof reference !== "string" || !/^(?:[1-9]|1[0-8])$/.test(reference)) {
            continue;
        }
        const existing = course.holes.get(reference);
        const candidateHasPar = parsePar(hole.tags.par) !== null;
        const existingHasPar = existing && parsePar(existing.tags.par) !== null;
        if (!existing || (candidateHasPar && !existingHasPar) ||
            (candidateHasPar === existingHasPar && hole.length > existing.length)) {
            course.holes.set(reference, hole);
        }
    }

    const tiles = new Map();
    const outputs = new Map();
    let mappedHoles = 0;
    for (const course of courses) {
        const lat = course.center[1];
        const lon = course.center[0];
        const tileLat = Math.floor(lat);
        const tileLon = Math.floor(lon);
        const references = [...course.holes.keys()].sort((left, right) => Number(left) - Number(right));
        const file = `courses/${course.type}_${course.osmId}.json`;
        course.roundCount = courseRoundCount(course.tags, references.length);
        const entries = references.map((reference) => {
            const hole = course.holes.get(reference);
            mappedHoles += 1;
            return {
                type: "way",
                id: hole.id,
                tags: {
                    golf: "hole",
                    ref: reference,
                    ...(parsePar(hole.tags.par) ? { par: parsePar(hole.tags.par) } : {})
                },
                geometry: [
                    { lat: hole.coordinates[0][1], lon: hole.coordinates[0][0] },
                    { lat: hole.target[1], lon: hole.target[0] }
                ]
            };
        });
        outputs.set(file, {
            id: course.id,
            name: course.name,
            attribution: "© OpenStreetMap contributors",
            license: "ODbL-1.0",
            elements: entries
        });
        const summary = {
            id: course.id,
            type: course.type,
            name: course.name,
            lat,
            lon,
            holes: references.length,
            count: course.roundCount,
            file
        };
        const key = `${tileLat}/${tileLon}`;
        if (!tiles.has(key)) {
            tiles.set(key, []);
        }
        tiles.get(key).push(summary);
    }

    for (let lat = MIN_TILE_LAT; lat <= MAX_TILE_LAT; lat += 1) {
        for (let lon = MIN_TILE_LON; lon <= MAX_TILE_LON; lon += 1) {
            const key = `${lat}/${lon}`;
            const tileCourses = (tiles.get(key) ?? []).sort((left, right) =>
                left.name.localeCompare(right.name, "es"));
            outputs.set(`tiles/${tileName(lat, lon)}`, {
                attribution: "© OpenStreetMap contributors",
                license: "ODbL-1.0",
                generatedAt,
                courses: tileCourses
            });
        }
    }

    outputs.set("metadata.json", {
        dataset: "Golfin Golfin Spain golf course catalog",
        generatedAt,
        source: "OpenStreetMap extracts from Geofabrik",
        attribution: "© OpenStreetMap contributors",
        license: "ODbL-1.0",
        licenseUrl: "https://www.openstreetmap.org/copyright",
        courseCount: courses.length,
        mappedHoleCount: mappedHoles,
        tileCount: (MAX_TILE_LAT - MIN_TILE_LAT + 1) * (MAX_TILE_LON - MIN_TILE_LON + 1),
        limitations: "Only OSM-mapped golf_course boundaries and numbered golf=hole ways are included."
    });

    return { outputs, courseCount: courses.length, mappedHoleCount: mappedHoles };
}

function run(executable, args) {
    const result = spawnSync(executable, args, { stdio: "inherit", windowsHide: true });
    if (result.error) {
        throw result.error;
    }
    if (result.status !== 0) {
        throw new Error(`${path.basename(executable)} failed with exit code ${result.status}`);
    }
}

function extractFeatures(osmium, pbfPath, workRoot) {
    const tempDir = fs.mkdtempSync(path.join(workRoot, "golf-osm-"));
    const filteredPath = path.join(tempDir, "golf-filtered.osm.pbf");
    const geoJsonPath = path.join(tempDir, "golf.geojson");
    try {
        run(osmium, [
            "tags-filter",
            "--no-progress",
            pbfPath,
            "w/leisure=golf_course",
            "r/leisure=golf_course",
            "w/golf=hole",
            "-o",
            filteredPath
        ]);
        run(osmium, [
            "export",
            "--no-progress",
            "--add-unique-id=type_id",
            filteredPath,
            "-o",
            geoJsonPath
        ]);
        const parsed = JSON.parse(fs.readFileSync(geoJsonPath, "utf8"));
        if (!Array.isArray(parsed.features)) {
            throw new Error(`osmium export produced invalid GeoJSON for ${pbfPath}`);
        }
        return parsed.features;
    } finally {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
}

function parseArguments(args) {
    const values = {};
    for (let index = 0; index < args.length; index += 1) {
        const argument = args[index];
        if (!argument.startsWith("--") || !args[index + 1]) {
            throw new Error(`Invalid argument: ${argument}`);
        }
        values[argument.slice(2)] = args[++index];
    }
    for (const required of ["spain", "canary", "output", "osmium"]) {
        if (!values[required]) {
            throw new Error(`Missing --${required}`);
        }
    }
    return values;
}

function main() {
    const args = parseArguments(process.argv.slice(2));
    const pbfPaths = [args.spain, args.canary].map((file) => path.resolve(file));
    for (const pbfPath of pbfPaths) {
        if (!fs.existsSync(pbfPath)) {
            throw new Error(`OSM extract not found: ${pbfPath}`);
        }
    }
    const osmium = path.resolve(args.osmium);
    const outputRoot = path.resolve(args.output);
    const workRoot = path.resolve(args.work ?? os.tmpdir());
    fs.mkdirSync(outputRoot, { recursive: true });
    fs.mkdirSync(workRoot, { recursive: true });
    const features = [];
    for (const pbfPath of pbfPaths) {
        console.log(`Extracting golf features from ${pbfPath}`);
        features.push(...extractFeatures(osmium, pbfPath, workRoot));
    }
    const result = buildCatalog(features);
    for (const [relativePath, content] of result.outputs) {
        const target = path.join(outputRoot, relativePath);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, `${JSON.stringify(content)}\n`, "utf8");
    }
    console.log(`Generated ${result.courseCount} courses and ${result.mappedHoleCount} numbered holes.`);
    console.log(`Catalog output: ${outputRoot}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
    try {
        main();
    } catch (error) {
        console.error(error instanceof Error ? error.message : error);
        process.exitCode = 1;
    }
}
