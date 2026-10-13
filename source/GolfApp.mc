import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class GolfApp extends Application.AppBase {
    var round;
    var courses;
    var recording;

    function initialize() {
        AppBase.initialize();
        round = new GolfRound();
        courses = new GolfCourses();
        recording = new GolfRecording(round, courses);
    }

    function onStart(state) {
        var saved = Application.Storage.getValue("session-v2");
        if (saved instanceof Lang.Dictionary) {
            courses.restore(saved["course"]);
            courses.restorePreferences(saved);
        }
        if (courses.course != null) {
            round.holeCount = courses.course["count"];
        }
        round.restore(saved instanceof Lang.Dictionary ? saved["round"] : Application.Storage.getValue("round-v1"));
        courses.applyPars(round, false);
    }

    function onStop(state) {
        if (recording.session != null) {
            recording.save();
        }
        courses.close();
        saveRound();
    }

    function saveRound() {
        try {
            Application.Storage.setValue("session-v2", { "round" => round.snapshot(), "course" => courses.course,
                "favorites" => courses.favorites, "yards" => courses.yards });
        } catch (exception) {
            courses.error = "Error guardado";
            WatchUi.requestUpdate();
        }
    }

    function getInitialView() {
        var view = new GolfView(round, courses, recording);
        return [view, new GolfDelegate(view, round, courses, recording)];
    }
}