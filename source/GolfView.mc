import Toybox.Graphics;
import Toybox.WatchUi;

class GolfView extends WatchUi.View {
    var round;
    var courses;
    var recording;
    var mode = :play;

    function initialize(golfRound, courseService, activityRecording) {
        View.initialize();
        round = golfRound;
        courses = courseService;
        recording = activityRecording;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var center = dc.getWidth() / 2;
        var heading = "HOYO " + (round.hole + 1).toString();
        var label = "GOLPES";
        var value = round.scores[round.hole].toString();
        var footer = "TOTAL " + round.total().toString();
        if (mode == :play) {
            var distance = courses.distance(round.hole);
            label = courses.targetLabel(round.hole) + courses.unitLabel();
            value = distance == null || distance > 9999 ? "--" : courses.displayDistance(distance).toString();
            footer = "G " + round.scores[round.hole].toString() + "  T " + round.total().toString();
            if (courses.course == null) {
                label = "SIN CAMPO";
            } else if (courses.currentHole(round.hole) == null) {
                label = "HOYO SIN DATOS";
            } else if (!courses.gpsEnabled) {
                label = "GPS APAGADO";
            } else if (!courses.hasFix()) {
                label = "BUSCANDO GPS";
            } else if (distance != null && distance > 9999) {
                label = "FUERA DEL CAMPO";
            }
            dc.drawCircle(137, 27, 14);
            dc.drawLine(130, 27, 144, 27);
            dc.drawLine(137, 20, 137, 34);
        } else if (mode == :summary) {
            heading = "VUELTA";
            label = "TOTAL";
            value = round.total().toString();
            footer = round.holeCount.toString() + " HOYOS";
        } else if (mode == :distance) {
            label = courses.targetLabel(round.hole) + courses.unitLabel();
            var distance = courses.distance(round.hole);
            value = distance == null || distance > 9999 ? "--" : courses.displayDistance(distance).toString();
            var hole = courses.currentHole(round.hole);
            footer = hole == null ? "Sin datos hoyo" : !courses.hasFix() ? "Sin GPS fiable" :
                hole["par"] == null ? "PAR --" : "PAR " + hole["par"].toString();
            if (distance != null && distance > 9999) {
                footer = "Fuera del campo";
            }
        } else if (mode == :shot) {
            heading = "GOLPE";
            label = courses.unitLabel();
            var measured = courses.shotDistance(round.hole);
            value = measured == null ? "--" : courses.displayDistance(measured).toString();
            footer = measured == null ? "Sin marca / GPS" : "Distancia recta";
        } else if (mode == :activity) {
            heading = "ACTIVIDAD";
            label = recording.status;
            value = (recording.duration() / 60).toNumber().toString();
            footer = "MIN  " + round.total().toString() + " GOLPES";
        }
        var parText = round.pars[round.hole] == null ? "PAR --" : "PAR " + round.pars[round.hole].toString();
        dc.drawText(52, 38, Graphics.FONT_XTINY, parText, Graphics.TEXT_JUSTIFY_CENTER);
        if (recording.active) {
            dc.fillCircle(9, 74, 3);
        }
        if (courses.busy) {
            footer = courses.status;
        } else if (courses.error != null) {
            footer = courses.error;
        }
        dc.drawText(52, 16, Graphics.FONT_XTINY, heading, Graphics.TEXT_JUSTIFY_CENTER);
        drawFitted(dc, center, 66, label, 142);
        var font = Graphics.FONT_NUMBER_HOT;
        if (dc.getTextWidthInPixels(value, font) > 142) {
            font = Graphics.FONT_NUMBER_MILD;
        }
        dc.drawText(center, 88, font, value, Graphics.TEXT_JUSTIFY_CENTER);
        drawFitted(dc, center, 130, footer, 138);
    }

    function drawFitted(dc, center, vertical, text, width) {
        while (text.length() > 0 && dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > width) {
            text = text.substring(0, text.length() - 1);
        }
        dc.drawText(center, vertical, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class GolfNumberView extends WatchUi.View {
    var title;
    var value;
    var minimum;
    var maximum;

    function initialize(label, initialValue, lowerBound, upperBound) {
        View.initialize();
        title = label;
        value = initialValue;
        minimum = lowerBound;
        maximum = upperBound;
    }

    function adjust(delta) {
        var updated = value + delta;
        if (updated >= minimum && updated <= maximum) {
            value = updated;
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var center = dc.getWidth() / 2;
        dc.drawText(52, 20, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawCircle(137, 27, 14);
        dc.drawLine(130, 27, 135, 32);
        dc.drawLine(135, 32, 144, 21);
        dc.drawText(center, 80, Graphics.FONT_NUMBER_HOT, value.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center, 130, Graphics.FONT_XTINY, minimum.toString() + " - " + maximum.toString(),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawLine(10, 83, 10, 69);
        dc.drawLine(10, 69, 6, 74);
        dc.drawLine(10, 69, 14, 74);
        dc.drawLine(10, 101, 10, 115);
        dc.drawLine(10, 115, 6, 110);
        dc.drawLine(10, 115, 14, 110);
    }
}