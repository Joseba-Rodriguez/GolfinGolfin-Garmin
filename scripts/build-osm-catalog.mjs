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
        const area = raw.match(/^a(\d+)$/);
        if (area) {
            const value = Number(area[1]);
            return value % 2 === 0 ? { type: "way", id: value / 2, area: true } :
                { type: "relation", id: (value - 1) / 2, area: true };
        }
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

function ringCentroid(ring) {
    const points = ring.length > 1 && ring[0][0] === ring[ring.length - 1][0] &&
        ring[0][1] === ring[ring.length - 1][1] ? ring.slice(0, -1) : ring;
    const sum = points.reduce((total, point) => [total[0] + point[0], total[1] + point[1]], [0, 0]);
    return [sum[0] / points.length, sum[1] / points.length];
}

function outerRing(geometry) {
    const polygons = polygonRings(geometry);
    if (!polygons.length) {
        return null;
    }
    return polygons.reduce((largest, polygon) => polygon[0].length > largest.length ? polygon[0] : largest, []);
}

// Distancia aproximada en metros, suficiente para emparejar elementos de un mismo campo.
function meters(left, right) {
    const radians = Math.PI / 180;
    const x = (right[0] - left[0]) * radians * Math.cos(((left[1] + right[1]) / 2) * radians);
    const y = (right[1] - left[1]) * radians;
    return Math.hypot(x, y) * 6371000;
}

function distanceToGeometry(geometry, point) {
    let best = Infinity;
    for (const polygon of polygonRings(geometry)) {
        for (const vertex of polygon[0]) {
            best = Math.min(best, meters(vertex, point));
        }
    }
    return best;
}

function holeReference(value) {
    if (typeof value !== "string") {
        return null;
    }
    const match = value.trim().match(/^(?:hole\s*)?([1-9]|1[0-8])$/i);
    return match ? match[1] : null;
}

// Frente y fondo del green a lo largo de la linea de juego tee -> green.
function greenPoints(ring, tee, center) {
    const result = { center };
    if (!ring || !tee) {
        return result;
    }
    const axis = [center[0] - tee[0], center[1] - tee[1]];
    const length = Math.hypot(axis[0], axis[1]);
    if (length === 0) {
        return result;
    }
    let front = null;
    let back = null;
    for (const vertex of ring) {
        const projection = ((vertex[0] - center[0]) * axis[0] + (vertex[1] - center[1]) * axis[1]) / length;
        if (!front || projection < front.projection) {
            front = { projection, vertex };
        }
        if (!back || projection > back.projection) {
            back = { projection, vertex };
        }
    }
    const project = (value) => [center[0] + (axis[0] / length) * value,
        center[1] + (axis[1] / length) * value];
    result.front = project(front.projection);
    result.back = project(back.projection);
    return result;
}

function roundCoordinate(value) {
    return Math.round(value * 1e7) / 1e7;
}

function point(coordinate) {
    return { lat: roundCoordinate(coordinate[1]), lon: roundCoordinate(coordinate[0]) };
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
    const courseIds = new Map();
    const holes = [];
    const greens = [];
    const markers = [];

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
            if (!bounds || courseIds.has(`${osm.type}/${osm.id}`)) {
                continue;
            }
            courseIds.set(`${osm.type}/${osm.id}`, true);
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
        } else if (tags.golf === "green" && polygonRings(feature.geometry).length) {
            const ring = outerRing(feature.geometry);
            if (ring && ring.length >= 3 && !greens.some((green) => green.id === osm.id)) {
                greens.push({ id: osm.id, ring, center: ringCentroid(ring), ref: holeReference(tags.ref), used: false });
            }
        } else if ((tags.golf === "pin" || tags.golf === "tee" || tags.golf === "green") &&
            feature.geometry?.type === "Point" && holeReference(tags.ref)) {
            markers.push({ kind: tags.golf, ref: holeReference(tags.ref), point: feature.geometry.coordinates });
        } else if (tags.golf === "tee" && polygonRings(feature.geometry).length && holeReference(tags.ref)) {
            const ring = outerRing(feature.geometry);
            if (ring && ring.length >= 3) {
                markers.push({ kind: "tee", ref: holeReference(tags.ref), point: ringCentroid(ring) });
            }
        } else if (tags.golf === "hole" && osm.type === "way" && !osm.area) {
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

    const smallest = (candidates) => candidates.sort((left, right) => left.bounds.area - right.bounds.area)[0];
    // Campo que contiene el punto; si ninguno, el mas cercano a menos de maxMeters de su limite.
    const courseFor = (target, alternative, maxMeters) => {
        let candidates = courses.filter((course) => geometryContains(course.geometry, target));
        if (!candidates.length && alternative) {
            candidates = courses.filter((course) => geometryContains(course.geometry, alternative));
        }
        if (candidates.length) {
            return smallest(candidates);
        }
        let best = null;
        for (const course of courses) {
            const margin = 0.01;
            if (target[0] < course.bounds.minLon - margin || target[0] > course.bounds.maxLon + margin ||
                target[1] < course.bounds.minLat - margin || target[1] > course.bounds.maxLat + margin) {
                continue;
            }
            const distance = distanceToGeometry(course.geometry, target);
            if (distance <= maxMeters && (!best || distance < best.distance)) {
                best = { course, distance };
            }
        }
        return best?.course ?? null;
    };

    for (const hole of holes) {
        const reference = holeReference(hole.tags.ref);
        if (!reference) {
            continue;
        }
        const course = courseFor(hole.target, hole.coordinates[0], 150);
        if (!course) {
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

    // Hoyos sin linea OSM: bandera o green numerado como destino y tee numerado como salida.
    for (const marker of markers) {
        if (marker.kind === "tee") {
            continue;
        }
        const course = courseFor(marker.point, null, 60);
        if (!course || course.holes.has(marker.ref)) {
            continue;
        }
        course.holes.set(marker.ref, { id: null, tags: { ref: marker.ref }, coordinates: [marker.point],
            target: marker.point, length: 0 });
    }
    for (const green of greens) {
        if (!green.ref) {
            continue;
        }
        const course = courseFor(green.center, null, 60);
        if (course && !course.holes.has(green.ref)) {
            course.holes.set(green.ref, { id: null, tags: { ref: green.ref }, coordinates: [green.center],
                target: green.center, length: 0 });
        }
    }
    for (const marker of markers) {
        if (marker.kind !== "tee") {
            continue;
        }
        const course = courseFor(marker.point, null, 60);
        const hole = course?.holes.get(marker.ref);
        if (hole && hole.coordinates.length === 1 && meters(marker.point, hole.target) < 700) {
            hole.coordinates = [marker.point, hole.target];
        }
    }
    for (const course of courses) {
        course.greens = greens.filter((green) => geometryContains(course.geometry, green.center) ||
            distanceToGeometry(course.geometry, green.center) < 60);
        for (const hole of course.holes.values()) {
            let match = null;
            for (const green of course.greens) {
                const distance = meters(green.center, hole.target);
                const inside = ringContains(green.ring, hole.target);
                if ((inside || distance < 35) && (!match || inside || distance < match.distance)) {
                    match = { green, distance };
                    if (inside) {
                        break;
                    }
                }
            }
            if (match) {
                match.green.used = true;
                hole.green = greenPoints(match.green.ring,
                    hole.coordinates.length > 1 ? hole.coordinates[0] : null, match.green.center);
            }
        }
    }

    const tiles = new Map();
    const outputs = new Map();
    let mappedHoles = 0;
    let mappedGreens = 0;
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
            const center = hole.green?.center ?? hole.target;
            return {
                type: "way",
                id: hole.id,
                tags: {
                    golf: "hole",
                    ref: reference,
                    ...(parsePar(hole.tags.par) ? { par: parsePar(hole.tags.par) } : {})
                },
                geometry: hole.coordinates.length > 1 ? [point(hole.coordinates[0]), point(center)] : [point(center)],
                ...(hole.green?.front ? { front: point(hole.green.front), back: point(hole.green.back) } : {})
            };
        });
        // Greens sin numerar: el reloj los usa como "green cercano" y para aprender el campo.
        const looseGreens = course.greens.filter((green) => !green.used).slice(0, 27)
            .map((green) => point(green.center));
        if (looseGreens.length) {
            mappedGreens += 1;
        }
        outputs.set(file, {
            id: course.id,
            name: course.name,
            attribution: "© OpenStreetMap contributors",
            license: "ODbL-1.0",
            elements: entries,
            ...(looseGreens.length ? { greens: looseGreens } : {})
        });
        const summary = {
            id: course.id,
            type: course.type,
            name: course.name,
            lat,
            lon,
            holes: references.length,
            greens: looseGreens.length,
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
        coursesWithLooseGreens: mappedGreens,
        tileCount: (MAX_TILE_LAT - MIN_TILE_LAT + 1) * (MAX_TILE_LON - MIN_TILE_LON + 1),
        limitations: "Only OSM-mapped golf_course boundaries, numbered golf=hole ways, numbered pins/greens/tees and green areas are included."
    });

    return { outputs, courseCount: courses.length, mappedHoleCount: mappedHoles, looseGreenCourses: mappedGreens };
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
            "w/golf=green",
            "r/golf=green",
            "n/golf=pin",
            "n/golf=green",
            "w/golf=tee",
            "n/golf=tee",
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
    if (values.geojson) {
        if (!values.output) {
            throw new Error("Missing --output");
        }
        return values;
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
    if (args.geojson) {
        const features = args.geojson.split(",").flatMap((file) =>
            JSON.parse(fs.readFileSync(path.resolve(file), "utf8")).features);
        writeCatalog(buildCatalog(features), path.resolve(args.output));
        return;
    }
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
    writeCatalog(buildCatalog(features), outputRoot);
}

function writeCatalog(result, outputRoot) {
    for (const [relativePath, content] of result.outputs) {
        const target = path.join(outputRoot, relativePath);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, `${JSON.stringify(content)}\n`, "utf8");
    }
    console.log(`Generated ${result.courseCount} courses and ${result.mappedHoleCount} numbered holes ` +
        `(${result.looseGreenCourses} courses with unnumbered greens).`);
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
