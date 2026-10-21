import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class GolfRecording {
    var session = null;
    var round;
    var courses;
    var active = false;
    var elapsed = 0;
    var startedAt = 0;
    var fields = [];
    var pulse;
    var status = "Sin grabacion";

    function initialize(golfRound, courseService) {
        round = golfRound;
        courses = courseService;
        pulse = new Timer.Timer();
    }

    function start() {
        try {
            if (session == null) {
                if (!(ActivityRecording has :SPORT_GOLF)) {
                    courses.error = "Golf FIT no disponible";
                    return false;
                }
                session = ActivityRecording.createSession({ :name => "Golfin Golfin",
                    :sport => ActivityRecording.SPORT_GOLF, :subSport => ActivityRecording.SUB_SPORT_GENERIC });
                fields = [];
                var names = ["Golf strokes", "Golf putts", "Golf penalties", "Golf holes"];
                for (var index = 0; index < names.size(); index += 1) {
                    fields.add(session.createField(names[index], index, FitContributor.DATA_TYPE_UINT16,
                        { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "count" }));
                }
                elapsed = 0;
            }
            if (active) {
                return true;
            }
            if (!session.start()) {
                courses.error = "No inicia actividad";
                return false;
            }
            active = true;
            startedAt = System.getTimer();
            status = "Grabando";
            courses.error = null;
            pulse.start(method(:onTick), 10000, true);
            return true;
        } catch (exception) {
            courses.error = "Error inicio FIT";
            return false;
        }
    }

    function pause() {
        if (!active) {
            return true;
        }
        try {
            if (!session.stop()) {
                courses.error = "No pausa actividad";
                return false;
            }
            elapsed += System.getTimer() - startedAt;
            active = false;
            pulse.stop();
            status = "En pausa";
            return true;
        } catch (exception) {
            courses.error = "Error pausa FIT";
            return false;
        }
    }

    function save() {
        if (session == null || !updateFields() || !pause()) {
            return false;
        }
        try {
            if (!session.save()) {
                courses.error = "No guarda actividad";
                return false;
            }
            session = null;
            fields = [];
            courses.error = null;
            status = "Actividad guardada";
            return true;
        } catch (exception) {
            courses.error = "Error guardado FIT";
            return false;
        }
    }

    function discard() {
        if (session == null || !pause()) {
            return false;
        }
        try {
            if (!session.discard()) {
                courses.error = "No descarta FIT";
                return false;
            }
            session = null;
            fields = [];
            elapsed = 0;
            status = "Actividad descartada";
            return true;
        } catch (exception) {
            courses.error = "Error descarte FIT";
            return false;
        }
    }

    function duration() {
        return (elapsed + (active ? System.getTimer() - startedAt : 0)) / 1000;
    }

    function onTick() {
        updateFields();
        WatchUi.requestUpdate();
    }

    function updateFields() {
        if (session == null) {
            return true;
        }
        try {
            var values = [round.total(), round.statistic(round.putts),
                round.statistic(round.penalties), round.completedCount()];
            for (var index = 0; index < fields.size(); index += 1) {
                fields[index].setData(values[index]);
            }
            return true;
        } catch (exception) {
            courses.error = "Error datos FIT";
            return false;
        }
    }
}