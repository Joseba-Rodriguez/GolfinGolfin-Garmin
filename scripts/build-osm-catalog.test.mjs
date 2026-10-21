import test from "node:test";
import assert from "node:assert/strict";
import { buildCatalog } from "./build-osm-catalog.mjs";

const course = {
    type: "Feature",
    properties: {
        "@id": "way/10",
        leisure: "golf_course",
        "golf:course": "9_hole",
        name: "Campo de prueba"
    },
    geometry: {
        type: "Polygon",
        coordinates: [[
            [-4.01, 40.01],
            [-3.99, 40.01],
            [-3.99, 40.03],
            [-4.01, 40.03],
            [-4.01, 40.01]
        ]]
    }
};

const hole = {
    type: "Feature",
    properties: { "@id": "way/20", golf: "hole", ref: "10", par: "4" },
    geometry: { type: "LineString", coordinates: [[-4.005, 40.015], [-4.002, 40.018]] }
};

test("builds a course tile and details with normalized OSM hole data", () => {
    const { outputs, courseCount, mappedHoleCount } = buildCatalog([course, hole], "2026-10-20");
    const tile = outputs.get("tiles/lat_40_lon_-4.json");
    const detail = outputs.get("courses/way_10.json");
    assert.equal(courseCount, 1);
    assert.equal(mappedHoleCount, 1);
    assert.equal(tile.courses.length, 1);
    assert.equal(tile.courses[0].id, "way/10");
    assert.equal(tile.courses[0].holes, 1);
    assert.equal(tile.courses[0].count, 9);
    assert.equal(tile.courses[0].file, "courses/way_10.json");
    assert.deepEqual(detail.elements[0], {
        type: "way",
        id: 20,
        tags: { golf: "hole", ref: "10", par: "4" },
        geometry: [
            { lat: 40.015, lon: -4.005 },
            { lat: 40.018, lon: -4.002 }
        ]
    });
    assert.equal(outputs.get("metadata.json").license, "ODbL-1.0");
});

test("does not attach a hole outside the course boundary or accept unnumbered holes", () => {
    const outside = structuredClone(hole);
    outside.geometry.coordinates = [[-4.5, 40.5], [-4.4, 40.4]];
    const unnumbered = structuredClone(hole);
    unnumbered.properties = { "@id": "way/21", golf: "hole", ref: "practice" };
    const { outputs, mappedHoleCount } = buildCatalog([course, outside, unnumbered]);
    assert.equal(mappedHoleCount, 0);
    assert.equal(outputs.get("courses/way_10.json").elements.length, 0);
});

test("merges official scorecard pars and hole count", () => {
    const card = { "way/10": { count: 9, pars: [3, 4, 4, 4, 3, 4, 3, 3, 5], source: "test" } };
    const noPar = structuredClone(hole);
    delete noPar.properties.par;
    const { outputs } = buildCatalog([course, noPar], "2026-10-21", card);
    const detail = outputs.get("courses/way_10.json");
    assert.deepEqual(detail.pars, [3, 4, 4, 4, 3, 4, 3, 3, 5]);
    assert.equal(detail.elements[0].tags.par, "3");
    assert.equal(outputs.get("tiles/lat_40_lon_-4.json").courses[0].pars, 1);
});

test("reads osmium multipolygon courses and adds green front/back and numbered pins", () => {
    const relationCourse = structuredClone(course);
    relationCourse.properties["@id"] = "a61";
    const green = {
        type: "Feature",
        properties: { "@id": "w30", golf: "green" },
        geometry: { type: "LineString", coordinates: [
            [-4.0022, 40.0178], [-4.0018, 40.0178], [-4.0018, 40.0182], [-4.0022, 40.0182], [-4.0022, 40.0178]
        ] }
    };
    const pin = {
        type: "Feature",
        properties: { "@id": "n40", golf: "pin", ref: "3" },
        geometry: { type: "Point", coordinates: [-4.008, 40.02] }
    };
    const loose = structuredClone(green);
    loose.properties["@id"] = "w31";
    loose.geometry.coordinates = loose.geometry.coordinates.map(([lon, lat]) => [lon + 0.005, lat + 0.005]);
    const { outputs, mappedHoleCount } = buildCatalog([relationCourse, hole, green, pin, loose]);
    const detail = outputs.get("courses/relation_30.json");
    assert.equal(mappedHoleCount, 2);
    const ten = detail.elements.find((element) => element.tags.ref === "10");
    assert.equal(ten.geometry.length, 2);
    assert.ok(ten.front.lat < ten.geometry[1].lat && ten.back.lat > ten.geometry[1].lat);
    const three = detail.elements.find((element) => element.tags.ref === "3");
    assert.deepEqual(three.geometry, [{ lat: 40.02, lon: -4.008 }]);
    assert.equal(detail.greens.length, 1);
});
