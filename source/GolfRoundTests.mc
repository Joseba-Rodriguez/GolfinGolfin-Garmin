import Toybox.Test;

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
        "center" => { "lat" => 40.4, "lon" => -3.7 } };
    var courses = parser.courses({ "elements" => [entry] });
    Test.assert(courses.size() == 1 && courses[0]["id"] == "123");
    Test.assert(parser.courses(null).size() == 0);
    Test.assert(parser.courses({ "elements" => [null, {}] }).size() == 0);
    entry["center"]["lat"] = 200;
    Test.assert(parser.courses({ "elements" => [entry] }).size() == 0);
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
    return true;
}

(:test)
function testCourseNumberingAndCache(logger) {
    var parser = new GolfCourseData();
    var first = { "tags" => { "golf" => "hole", "ref" => "1" } };
    var ninth = { "tags" => { "golf" => "hole", "ref" => "9" } };
    var numbers = parser.holeNumbers({ "elements" => [ninth, first] });
    Test.assert(numbers.size() == 2 && numbers[0] == 1 && numbers[1] == 9);
    Test.assert(parser.holeNumbers({ "elements" => [first, first] }).size() == 0);
    Test.assert(parser.holeNumbers({ "remark" => "incomplete", "elements" => [first] }).size() == 0);
    var holes = [];
    for (var index = 0; index < 18; index += 1) {
        holes.add(null);
    }
    var saved = { "name" => "Campo", "count" => 9, "holes" => holes };
    Test.assert(!parser.validCachedCourse(saved));
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
    Test.assert(service.displayDistance(100) == 109 && service.unitLabel() == "yd");
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
    Test.assert(service.error == "No guarda actividad");
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

(:test)
function testDownloadErrorsAndOldResponses(logger) {
    var service = new GolfCourses();
    service.busy = true;
    service.requestId = 5;
    service.onResponse(200, { "elements" => [] }, 4);
    Test.assert(service.busy && service.requestId == 5);
    service.onResponse(429, null, 5);
    Test.assert(!service.busy && service.error == "API ocupada" && service.course == null);
    service.busy = true;
    service.onResponse(200, { "remark" => "timeout", "elements" => [] }, service.requestId);
    Test.assert(!service.busy && service.error == "Error red/API");
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