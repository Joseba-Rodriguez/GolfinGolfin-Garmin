import Toybox.Position;
import Toybox.System;
import Toybox.Application;
import Toybox.Test;
import Toybox.Lang;

(:test)
function testRoundBoundaries(logger) {
    var round = new GolfRound();
    round.changeScore(-1);
    Test.assert(round.scores[0] == 0);
    for (var index = 0; index < 100; index += 1) {
        round.changeScore(1);
    }
    Test.assert(round.scores[0] == 99);
    round.changeHole(-1);
    Test.assert(round.hole == 0);
    for (var index = 0; index < 18; index += 1) {
        round.changeHole(1);
    }
    Test.assert(round.hole == 17);
    round.changeScore(1);
    Test.assert(round.total() == 100);
    round.reset();
    Test.assert(round.total() == 0 && round.hole == 0);
    return true;
}

(:test)
function testRoundRestore(logger) {
    var original = new GolfRound();
    original.changeHole(1);
    original.changeScore(1);
    var restored = new GolfRound();
    restored.restore(original.snapshot());
    Test.assert(restored.hole == 1 && restored.total() == 1);
    restored.restore(null);
    restored.restore({ "hole" => 19, "scores" => [] });
    restored.restore({ "hole" => 0, "scores" => [1] });
    Test.assert(restored.hole == 1 && restored.total() == 1);
    return true;
}

(:test)
function testPublicCourseParsing(logger) {
    var parser = new GolfCourseData();
    var entry = { "type" => "way", "id" => 123,
        "tags" => { "leisure" => "golf_course", "name" => "Campo de prueba" },
        "bounds" => { "minlat" => 40.3, "minlon" => -3.8, "maxlat" => 40.5, "maxlon" => -3.6 } };
    var courses = parser.courses({ "elements" => [entry] });
    Test.assert(courses.size() == 1 && courses[0]["id"].equals("123"));
    Test.assert(courses[0]["bounds"]["minlat"] == 40.3 && courses[0]["bounds"]["maxlon"] == -3.6);
    Test.assert(courses[0]["lat"] > 40.39 && courses[0]["lat"] < 40.41 &&
        courses[0]["lon"] > -3.71 && courses[0]["lon"] < -3.69);
    var service = new GolfCourses();
    var nearby = service.closestCourses(courses, { "lat" => 40.4, "lon" => -3.7 });
    Test.assert(nearby.size() == 1 && nearby[0]["id"].equals("123"));
    Test.assert(parser.courses(null).size() == 0);
    Test.assert(parser.courses({ "elements" => [null, {}] }).size() == 0);
    entry["center"] = { "lat" => 200, "lon" => -3.7 };
    courses = parser.courses({ "elements" => [entry] });
    Test.assert(courses.size() == 1 && courses[0]["lat"] > 40.39 && courses[0]["lat"] < 40.41);
    entry["center"] = null;
    entry["bounds"]["maxlat"] = 200;
    Test.assert(parser.courses({ "elements" => [entry] }).size() == 0);
    entry["bounds"]["maxlat"] = 40.5;
    entry["bounds"]["maxlon"] = -4.0;
    Test.assert(parser.courses({ "elements" => [entry] }).size() == 0);
    entry["bounds"] = null;
    Test.assert(parser.courses({ "elements" => [entry] }).size() == 0);
    return true;
}

(:test)
function testStaticCatalogParsing(logger) {
    var parser = new GolfCourseData();
    var catalog = { "courses" => [
        { "id" => "way/123", "type" => "way", "name" => "Campo estatico",
            "lat" => 40.4, "lon" => -3.7, "holes" => 9, "count" => 9,
            "file" => "courses/way_123.json" },
        { "id" => "relation/456", "type" => "relation", "name" => "Campo sin hoyos GPS",
            "lat" => 40.5, "lon" => -3.6, "holes" => 0, "count" => 18,
            "file" => "courses/relation_456.json" },
        { "id" => "way/789", "type" => "way", "name" => "Ruta invalida",
            "lat" => 40.4, "lon" => -3.7, "holes" => 18, "count" => 18,
            "file" => "courses/../private.json" },
        { "id" => "way/999", "type" => "way", "name" => "Coordenadas invalidas",
            "lat" => 200, "lon" => -3.7, "holes" => 18, "count" => 18,
            "file" => "courses/way_999.json" }
    ] };
    var courses = parser.catalogCourses(catalog);
    Test.assert(courses.size() == 2);
    Test.assert(courses[0]["id"].equals("way/123") && courses[0]["holes"] == 9);
    Test.assert(courses[1]["holes"] == 0 && courses[1]["file"].equals("courses/relation_456.json"));
    Test.assert(parser.catalogCourses(null).size() == 0);
    return true;
}

(:test)
function testCatalogTilesStayInsideCoverageAndAreUnique(logger) {
    var service = new GolfCourses();
    var madridTiles = service.catalogTilesFor([40.41678, -3.70379]);
    Test.assert(madridTiles.size() == 1 &&
        madridTiles[0].equals("tiles/lat_40_lon_-4.json"));
    var canaryTiles = service.catalogTilesFor([28.1, -15.4]);
    Test.assert(canaryTiles.size() > 0 && canaryTiles.size() <= 9);
    Test.assert(service.catalogTilesFor([51.5, -0.12]).size() == 0);
    Test.assert(service.catalogTilesFor([40.0, -4.0]).size() <= 9);
    return true;
}

(:test)
function testNearbyCoursesAreFilteredAndOrdered(logger) {
    var service = new GolfCourses();
    var origin = { "lat" => 40.4, "lon" => -3.7 };
    var candidates = [
        { "id" => "far", "lat" => 40.7, "lon" => -3.7 },
        { "id" => "near", "lat" => 40.401, "lon" => -3.7 },
        { "id" => "middle", "lat" => 40.45, "lon" => -3.7 }
    ];
    var nearby = service.closestCourses(candidates, origin);
    Test.assert(nearby.size() == 2);
    Test.assert(nearby[0]["id"].equals("near") && nearby[1]["id"].equals("middle"));
    return true;
}

(:test)
function testEmptyCourseSearchShowsResultAndCanRetry(logger) {
    var service = new GolfCourses();
    service.busy = true;
    service.searchOrigin = { "lat" => 40.4, "lon" => -3.7 };
    service.catalogTiles = ["tiles/lat_40_lon_-4.json"];
    service.catalogTileIndex = 0;
    service.phase = :catalogTile;
    service.staticRequest = true;
    service.requestId = 7;
    service.onResponse(200, { "license" => "ODbL-1.0", "courses" => [] }, 7);
    Test.assert(!service.busy && service.nearby.size() == 0);
    Test.assert(service.status.equals("Sin campos OSM"));
    Test.assert(service.error.equals("Sin campos en 20 km"));
    return true;
}

(:test)
function testOfflineCourseSaveAndReplacement(logger) {
    var service = new GolfCourses();
    var first = { "name" => "Campo 1" };
    var second = { "name" => "Campo 2" };
    var third = { "name" => "Campo 3" };
    var fourth = { "name" => "Campo 4" };
    service.favorites = [first, second, third];
    Test.assert(service.favoritesIncluding(fourth, null) == null);
    var replaced = service.favoritesIncluding(fourth, 1);
    Test.assert(replaced.size() == 3 && replaced[0]["name"].equals("Campo 1") &&
        replaced[1]["name"].equals("Campo 4") && replaced[2]["name"].equals("Campo 3"));
    Test.assert(service.favoriteIndex("Campo 2") != null && service.favoriteIndex("Campo 2") == 1);
    var refreshedCourse = { "name" => "Campo 2", "revision" => 2 };
    var refreshed = service.favoritesIncluding(refreshedCourse, null);
    Test.assert(refreshed.size() == 3 && refreshed[1]["revision"] == 2);
    return true;
}

(:test)
function testBackNineHoleOrderIsNormalized(logger) {
    var service = new GolfCourses();
    var holes = [] as Lang.Array<Lang.Dictionary or Null>;
    for (var index = 0; index < 18; index += 1) {
        holes.add(null);
    }
    var course = { "count" => 9, "holes" => holes };
    var hole10 = { "tags" => { "golf" => "hole", "ref" => "10" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.401, "lon" => -3.701 }] };
    var hole18 = { "tags" => { "golf" => "hole", "ref" => "18" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.409, "lon" => -3.709 }] };
    Test.assert(service.storeDownloadedHole(course, 0, 10, { "elements" => [hole10] }));
    Test.assert(service.storeDownloadedHole(course, 8, 18, { "elements" => [hole18] }));
    Test.assert(holes[0]["lat"] == 40.401 && holes[8]["lat"] == 40.409 && holes[9] == null);
    Test.assert(!service.storeDownloadedHole(course, 9, 18, { "elements" => [hole18] }));
    return true;
}

(:test)
function testDownloadedCourseIsSavedAndLoadable(logger) {
    var service = new GolfCourses();
    var controller = new GolfTestCourseController();
    service.controller = controller;
    service.busy = true;
    service.staticRequest = true;
    service.phase = :detail;
    service.requestId = 9;
    var holes = [];
    for (var index = 0; index < 18; index += 1) {
        holes.add(null);
    }
    service.draft = { "id" => "way/123", "type" => "way", "name" => "Campo 9 hoyos",
        "source" => "osm", "count" => 9, "holes" => holes };
    var hole10 = { "tags" => { "golf" => "hole", "ref" => "10", "par" => "4" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.401, "lon" => -3.701 }] };
    var duplicateHole10 = { "tags" => { "golf" => "hole", "ref" => "10" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }] };
    service.onResponse(200, { "id" => "way/123", "name" => "Campo 9 hoyos", "license" => "ODbL-1.0",
        "elements" => [duplicateHole10, hole10] }, 9);
    Test.assert(!service.busy && service.course["count"] == 9);
    Test.assert(service.favorites.size() == 1 && service.favorites[0]["name"].equals("Campo 9 hoyos"));
    Test.assert(service.course["holes"][0]["par"] == 4 && controller.round.holeCount == 9);
    var length = service.holeLength(0);
    Test.assert(length != null && length >= 135 && length <= 145);
    Test.assert(service.holeLength(1) == null);
    service.useFavorite(0);
    Test.assert(controller.round.holeCount == 9 && controller.round.pars[0] == 4 &&
        controller.round.total() == 0 && controller.view.mode == :play);
    service.stopGps();
    return true;
}

(:test)
function testStaticCourseDetailIsSavedOffline(logger) {
    var service = new GolfCourses();
    var controller = new GolfTestCourseController();
    service.controller = controller;
    service.busy = true;
    service.staticRequest = true;
    service.phase = :detail;
    service.requestId = 91;
    service.replacementFavorite = null;
    service.draft = { "id" => "way/321", "type" => "way", "name" => "Campo estatico",
        "source" => "osm", "count" => 9, "holes" => [] };
    for (var index = 0; index < 18; index += 1) {
        service.draft["holes"].add(null);
    }
    var hole = { "type" => "way", "id" => 654,
        "tags" => { "golf" => "hole", "ref" => "10", "par" => "4" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.401, "lon" => -3.701 }] };
    service.onResponse(200, { "id" => "way/321", "name" => "Campo estatico",
        "license" => "ODbL-1.0", "elements" => [hole] }, 91);
    Test.assert(!service.busy && service.course["count"] == 9);
    Test.assert(service.course["holes"][0]["par"] == 4 && service.course["holes"][0]["lat"] == 40.401);
    Test.assert(service.favorites.size() == 1 && service.favorites[0]["id"].equals("way/321"));
    Test.assert(controller.round.holeCount == 9 && controller.round.pars[0] == 4);
    return true;
}

(:test)
function testRoundHistoryKeepsLastRounds(logger) {
    var history = new GolfHistory();
    history.rounds = [];
    var round = new GolfRound();
    round.holeCount = 9;
    Test.assert(!history.archive(round, "Vacio") && history.rounds.size() == 0);
    round.setPar(4);
    round.changeScore(5);
    round.changePutts(2);
    for (var index = 0; index < 7; index += 1) {
        history.archive(round, "Campo " + index.toString());
    }
    Test.assert(history.rounds.size() == 5 && history.rounds[0]["name"].equals("Campo 6"));
    var entry = history.rounds[0];
    Test.assert(history.validEntry(entry) && entry["count"] == 9 && entry["putts"][0] == 2);
    Test.assert(history.total(entry) == 5 && history.relative(entry) == 1);
    round.changeScore(1);
    Test.assert(entry["scores"][0] == 5);
    Test.assert(history.relativeLabel(null).equals("PAR --") && history.relativeLabel(-2).equals("-2"));
    Application.Storage.deleteValue("history-v1");
    return true;
}

(:test)
function testPublicHoleParsing(logger) {
    var parser = new GolfCourseData();
    var entry = { "tags" => { "golf" => "hole", "ref" => "2", "par" => "4" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.401, "lon" => -3.701 }] };
    var holes = parser.holes({ "elements" => [entry] });
    Test.assert(holes.size() == 18 && holes[0] == null);
    Test.assert(holes[1]["par"] == 4 && holes[1]["lat"] == 40.401);
    Test.assert(parser.holes({ "elements" => [entry, entry] }).size() == 0);
    entry["tags"]["ref"] = "2A";
    Test.assert(parser.holes({ "elements" => [entry] })[1] == null);
    Test.assert(parser.holes({ "remark" => "timeout", "elements" => [entry] })[1] == null);
    var invalidGeometry = { "tags" => { "golf" => "hole", "ref" => "2" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }] };
    var duplicateWithPar = { "tags" => { "golf" => "hole", "ref" => "2", "par" => "4" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.402, "lon" => -3.702 }] };
    var selected = parser.holeForNumber({ "elements" => [invalidGeometry, entry, duplicateWithPar] }, 2);
    Test.assert(selected != null && selected["par"] == 4 && selected["lat"] == 40.402);
    return true;
}

(:test)
function testCourseNumberingAndCache(logger) {
    var parser = new GolfCourseData();
    var first = { "tags" => { "golf" => "hole", "ref" => "1" } };
    var ninth = { "tags" => { "golf" => "hole", "ref" => "9" } };
    var numbers = parser.holeNumbers({ "elements" => [ninth, first] });
    Test.assert(numbers.size() == 2 && numbers[0] == 1 && numbers[1] == 9);
    var backNine = [];
    for (var number = 10; number <= 18; number += 1) {
        backNine.add({ "tags" => { "golf" => "hole", "ref" => number.toString() } });
    }
    numbers = parser.holeNumbers({ "elements" => backNine });
    Test.assert(numbers.size() == 9 && numbers[0] == 10 && numbers[8] == 18);
    numbers = parser.holeNumbers({ "elements" => [first, first, ninth] });
    Test.assert(numbers.size() == 2 && numbers[0] == 1 && numbers[1] == 9);
    var unnumbered = { "tags" => { "golf" => "hole", "ref" => "1A" } };
    Test.assert(parser.holeNumbers({ "elements" => [unnumbered, first] }).size() == 1);
    Test.assert(parser.holeNumbers({ "remark" => "incomplete", "elements" => [first] }).size() == 0);
    var holes = [] as Lang.Array<Lang.Dictionary or Null>;
    for (var index = 0; index < 18; index += 1) {
        holes.add(null);
    }
    var saved = { "name" => "Campo", "count" => 9, "holes" => holes };
    Test.assert(!parser.validCachedCourse(saved));
    saved["source"] = "osm";
    Test.assert(parser.validCachedCourse(saved));
    saved["source"] = null;
    holes[8] = { "lat" => 40.4, "lon" => -3.7, "par" => 4 };
    Test.assert(parser.validCachedCourse(saved));
    holes[9] = holes[8];
    Test.assert(!parser.validCachedCourse(saved));
    holes[9] = null;
    holes[8]["par"] = "4";
    Test.assert(!parser.validCachedCourse(saved));
    return true;
}

(:test)
function testGolfDistances(logger) {
    var parser = new GolfCourseData();
    var origin = { "lat" => 0.0, "lon" => 0.0 };
    Test.assert(parser.distanceMeters(origin, origin) == 0);
    var north = parser.distanceMeters(origin, { "lat" => 0.001d, "lon" => 0.0d });
    Test.assert(north >= 110 && north <= 112);
    var east = parser.distanceMeters(origin, { "lat" => 0.0d, "lon" => 0.001d });
    Test.assert(east >= 110 && east <= 112);
    var acrossDateLine = parser.distanceMeters({ "lat" => 0.0d, "lon" => 179.999d },
        { "lat" => 0.0d, "lon" => -179.999d });
    Test.assert(acrossDateLine >= 221 && acrossDateLine <= 224);
    Test.assert(parser.distanceMeters(null, origin) == null);
    Test.assert(parser.distanceMeters(origin, { "lat" => 91, "lon" => 0 }) == null);
    return true;
}

(:test)
function testNineHoleRound(logger) {
    var round = new GolfRound();
    round.holeCount = 9;
    for (var index = 0; index < 18; index += 1) {
        round.changeHole(1);
    }
    Test.assert(round.hole == 8);
    round.changeScore(4);
    round.scores[9] = 99;
    Test.assert(round.total() == 4);
    round.reset();
    Test.assert(round.total() == 0 && round.holeCount == 9);
    return true;
}

(:test)
function testFinishedRoundLocksAndRestores(logger) {
    var round = new GolfRound();
    round.holeCount = 9;
    round.setPar(4);
    round.changeScore(5);
    round.finishRound();
    Test.assert(round.finished && round.completedCount() == 1 && round.relativeScore() == 1);
    round.changeScore(1);
    round.setPar(3);
    round.changePutts(1);
    round.changePenalty(1);
    Test.assert(round.scores[0] == 5 && round.pars[0] == 4);
    var restored = new GolfRound();
    restored.holeCount = 9;
    restored.restore(round.snapshot());
    Test.assert(restored.finished && restored.holeCount == 9 && restored.scores[0] == 5);
    restored.reset();
    Test.assert(!restored.finished && restored.total() == 0 && restored.pars[0] == 4);
    restored.holeCount = 9;
    for (var index = 0; index < 18; index += 1) {
        restored.changeHole(1);
    }
    Test.assert(restored.hole == 8);
    return true;
}

(:test)
function testScoringStatistics(logger) {
    var round = new GolfRound();
    Test.assert(!round.finishHole() && round.relativeScore() == null);
    round.setPar(4);
    round.changeScore(3);
    round.changePutts(1);
    round.changePenalty(1);
    Test.assert(round.scores[0] == 4 && round.penalties[0] == 1);
    Test.assert(round.finishHole() && round.relativeScore() == 0);
    round.changeScore(-3);
    Test.assert(round.scores[0] == 4);
    round.changeHole(1);
    round.changeScore(5);
    round.finishHole();
    Test.assert(round.relativeScore() == null);
    round.setPar(4);
    Test.assert(round.relativeScore() == 1 && round.completedCount() == 2);
    Test.assert(round.statistic(round.putts) == 1 && round.statistic(round.penalties) == 1);
    var restored = new GolfRound();
    restored.restore(round.snapshot());
    Test.assert(restored.relativeScore() == 1 && restored.putts[0] == 1);
    round.reset();
    Test.assert(round.total() == 0 && round.completedCount() == 0 && round.pars[0] == 4);
    return true;
}

(:test)
function testHoleCelebrationResults(logger) {
    var round = new GolfRound();
    Test.assert(round.resultForHole(0) == null);
    round.setPar(4);
    Test.assert(round.resultForHole(0) == null);
    round.changeScore(2);
    Test.assert(round.resultForHole(0) == :eagle);
    round.changeScore(1);
    Test.assert(round.resultForHole(0) == :birdie);
    round.changeScore(1);
    Test.assert(round.resultForHole(0) == :par);
    round.changeScore(1);
    Test.assert(round.resultForHole(0) == :bogey);
    round.changeScore(1);
    Test.assert(round.resultForHole(0) == :doubleBogey);
    round.changeScore(1);
    Test.assert(round.resultForHole(0) == :tripleBogey);
    Test.assert(round.resultForHole(-1) == null && round.resultForHole(18) == null);
    return true;
}

(:test)
function testManualFieldAndUnits(logger) {
    var service = new GolfCourses();
    var holes = [];
    for (var index = 0; index < 18; index += 1) {
        holes.add(null);
    }
    var manual = { "name" => "Campo manual", "count" => 9, "source" => "manual", "holes" => holes };
    Test.assert(service.parser.validCachedCourse(manual));
    service.restore(manual);
    var round = new GolfRound();
    round.pars[0] = 5;
    service.applyPars(round, true);
    Test.assert(round.pars[0] == null && service.distance(0) == null);
    Test.assert(service.displayDistance(100) == 100);
    service.yards = true;
    Test.assert(service.displayDistance(100) == 109 && service.unitLabel().equals("yd"));
    Test.assert(!service.markShot(0) && !service.markGreen(round));
    manual["count"] = 27;
    Test.assert(!service.parser.validCachedCourse(manual));
    return true;
}

(:test)
function testRecordingFailureKeepsSession(logger) {
    var round = new GolfRound();
    var service = new GolfCourses();
    var recorder = new GolfRecording(round, service);
    var fake = new GolfFailedSession();
    recorder.session = fake;
    Test.assert(!recorder.save() && recorder.session == fake);
    Test.assert(service.error.equals("No guarda actividad"));
    Test.assert(!recorder.discard() && recorder.session == fake);
    recorder.active = true;
    Test.assert(!recorder.pause() && recorder.active);
    return true;
}

class GolfFailedSession {
    function initialize() {
    }

    function save() {
        return false;
    }

    function discard() {
        return false;
    }

    function stop() {
        return false;
    }
}

class GolfTestCourseController {
    var round;
    var view;
    var recording;

    function initialize() {
        round = new GolfRound();
        view = new GolfTestCourseView();
        recording = new GolfTestCourseRecording();
    }

    function persist() {
    }
}

class GolfTestCourseView {
    var mode = :summary;
}

class GolfTestCourseRecording {
    var session = null;
}

(:test)
function testDownloadErrorsAndOldResponses(logger) {
    var service = new GolfCourses();
    Test.assert(service.networkError(-104).equals("Sin movil conectado"));
    Test.assert(service.networkError(-400).equals("Respuesta no JSON"));
    Test.assert(service.networkError(500).equals("Error HTTP 500"));
    service.busy = true;
    service.staticRequest = true;
    service.phase = :detail;
    service.requestId = 5;
    service.onResponse(200, { "elements" => [] }, 4);
    Test.assert(service.busy && service.requestId == 5);
    service.onResponse(404, null, 5);
    Test.assert(!service.busy && service.error.equals("Ficha no publicada") && service.course == null);
    service.busy = true;
    service.phase = :detail;
    service.draft = { "id" => "way/1", "name" => "X", "count" => 18, "holes" => [] };
    service.onResponse(200, { "id" => "way/2", "license" => "ODbL-1.0", "elements" => [] }, service.requestId);
    Test.assert(!service.busy && service.error.equals("Ficha OSM invalida"));
    Test.assert(service.distance(0) == null);
    return true;
}

(:test)
function testNumberEditorBounds(logger) {
    var editor = new GolfNumberView("GOLPES", 4, 2, 99);
    editor.adjust(-3);
    Test.assert(editor.value == 4);
    editor.adjust(-2);
    Test.assert(editor.value == 2);
    editor.adjust(-1);
    Test.assert(editor.value == 2);
    editor.adjust(97);
    Test.assert(editor.value == 99);
    editor.adjust(1);
    Test.assert(editor.value == 99);
    var putting = new GolfNumberView("PUTTS", 0, 0, 0);
    putting.adjust(1);
    Test.assert(putting.value == 0);
    return true;
}
(:test)
function testFrontBackAndLooseGreensAreParsed(logger) {
    var parser = new GolfCourseData();
    var entry = { "tags" => { "golf" => "hole", "ref" => "1", "par" => "4" },
        "geometry" => [{ "lat" => 40.4, "lon" => -3.7 }, { "lat" => 40.403, "lon" => -3.7 }],
        "front" => { "lat" => 40.4029, "lon" => -3.7 }, "back" => { "lat" => 40.4031, "lon" => -3.7 } };
    var hole = parser.holeForNumber({ "elements" => [entry] }, 1);
    Test.assert(hole["flat"] == 40.4029 && hole["blat"] == 40.4031 && hole["tlat"] == 40.4);
    var pinOnly = { "tags" => { "golf" => "hole", "ref" => "2" }, "geometry" => [{ "lat" => 40.41, "lon" => -3.7 }] };
    hole = parser.holeForNumber({ "elements" => [pinOnly] }, 2);
    Test.assert(hole != null && hole["lat"] == 40.41 && hole["tlat"] == null && hole["flat"] == null);
    var greens = parser.looseGreens({ "greens" => [{ "lat" => 40.5, "lon" => -3.7 }, { "lat" => 99, "lon" => 0 }] });
    Test.assert(greens.size() == 1);
    return true;
}

(:test)
function testCourseLearnsGreensAndTees(logger) {
    var service = new GolfCourses();
    var holes = [];
    for (var index = 0; index < 18; index += 1) {
        holes.add(null);
    }
    service.course = { "id" => "way/9", "name" => "Nuevo", "count" => 9, "source" => "osm", "holes" => holes,
        "greens" => [{ "lat" => 40.4031, "lon" => -3.7 }, { "lat" => 40.5, "lon" => -3.7 }] };
    service.favorites = [service.course];
    Test.assert(service.targetLabel(0).equals("GREEN CERCANO"));
    Test.assert(!service.learnTee(0) && !service.learnGreen(0, 4));
    service.location = new Position.Location({ :latitude => 40.4, :longitude => -3.7, :format => :degrees });
    service.fixTime = System.getTimer();
    Test.assert(service.learnTee(0) && service.pendingTee["hole"] == 0);
    service.location = new Position.Location({ :latitude => 40.403, :longitude => -3.7, :format => :degrees });
    Test.assert(service.learnGreen(0, 4));
    var learned = service.course["holes"][0];
    Test.assert(learned["lat"] == 40.4031 && learned["tlat"] != null && learned["par"] == 4);
    Test.assert(service.course["greens"].size() == 1 && service.learnedHoles() == 1);
    Test.assert(service.targetLabel(0).equals("APRENDIDO") && service.parser.validCachedCourse(service.course));
    var length = service.holeLength(0);
    Test.assert(length >= 340 && length <= 350);
    Test.assert(!service.learnGreen(0, 4));
    service.location = new Position.Location({ :latitude => 40.45, :longitude => -3.7, :format => :degrees });
    Test.assert(service.learnGreen(1, null) && service.course["holes"][1]["lat"] < 40.4501);
    return true;
}
