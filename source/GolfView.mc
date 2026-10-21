import Toybox.Graphics;
import Toybox.Timer;
import Toybox.WatchUi;

class GolfView extends WatchUi.View {
    var round;
    var courses;
    var recording;
    var mode = :play;
    var celebration;
    var celebrationFrame = 0;
    var celebrationHole = 0;
    var celebrationTimer;

    function initialize(golfRound, courseService, activityRecording) {
        View.initialize();
        round = golfRound;
        courses = courseService;
        recording = activityRecording;
        celebrationTimer = new Timer.Timer();
    }

    function showCelebration(result, holeNumber) {
        celebration = result;
        celebrationHole = holeNumber;
        celebrationFrame = 0;
        celebrationTimer.start(method(:onCelebrationTick), 120, true);
        WatchUi.requestUpdate();
    }

    function onCelebrationTick() {
        celebrationFrame += 1;
        if (celebrationFrame >= 22) {
            celebrationTimer.stop();
            celebration = null;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var center = dc.getWidth() / 2;
        if (celebration != null) {
            drawCelebration(dc, center);
            return;
        }
        if (mode == :play) {
            drawPlayScreen(dc, center);
            return;
        }
        var heading = "HOYO " + (round.hole + 1).toString();
        var label = "GOLPES";
        var value = round.scores[round.hole].toString();
        var footer = "TOTAL " + round.total().toString();
        if (mode == :summary) {
            heading = round.finished ? "VUELTA FINALIZADA" : "RESUMEN VUELTA";
            label = "TOTAL GOLPES";
            value = round.total().toString();
            var relative = round.relativeScore();
            footer = round.completedCount().toString() + "/" + round.holeCount.toString() + " HOYOS";
            footer += relative == null ? "  PAR --" :
                (relative > 0 ? "  +" : "  ") + relative.toString() + " AL PAR";
        } else if (mode == :distance) {
            label = courses.targetLabel(round.hole) + courses.unitLabel();
            var distance = courses.distance(round.hole);
            value = distance == null || distance > 9999 ? "--" : courses.displayDistance(distance).toString();
            var hole = courses.currentHole(round.hole);
            var length = courses.holeLength(round.hole);
            footer = hole == null ? "Sin datos hoyo" : !courses.hasFix() ? "Sin GPS fiable" :
                (hole["par"] == null ? "PAR --" : "PAR " + hole["par"].toString()) +
                (length == null ? "" : "  " + courses.displayDistance(length).toString() + courses.unitLabel());
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

    function drawPlayScreen(dc, center) {
        var holeNumber = round.hole + 1;
        var par = round.pars[round.hole];
        dc.drawText(center - 58, 23, Graphics.FONT_XTINY,
            "HOYO " + holeNumber.toString() + "/" + round.holeCount.toString(), Graphics.TEXT_JUSTIFY_LEFT);
        var parCenter = center + 58;
        var parText = par == null ? "PAR --" : "PAR " + par.toString();
        dc.drawText(parCenter, 17, Graphics.FONT_XTINY, parText, Graphics.TEXT_JUSTIFY_CENTER);

        var target = courses.currentHole(round.hole);
        var distance = courses.distance(round.hole);
        var status = null;
        if (courses.busy) {
            status = courses.status;
        } else if (courses.error != null) {
            status = courses.error;
        } else if (courses.course == null) {
            status = "MENU > CAMPOS";
        } else if (target == null) {
            status = "Este hoyo no tiene datos";
        } else if (!courses.gpsEnabled) {
            status = "Activa el GPS en el menu";
        } else if (!courses.hasFix()) {
            status = "Esperando senal GPS";
        } else if (distance != null && distance > 9999) {
            status = "GPS fuera del campo";
        }

        if (courses.course == null || target == null) {
            var emptyTitle = courses.course == null ? "SIN CAMPO" : "HOYO SIN DATOS";
            dc.drawText(center, 60, Graphics.FONT_MEDIUM, emptyTitle, Graphics.TEXT_JUSTIFY_CENTER);
            drawFitted(dc, center, 83, status, 124);
        } else {
            drawFitted(dc, center, 44, courses.targetLabel(round.hole) + "AL GREEN", 112);
            if (distance == null || distance > 9999) {
                dc.drawText(center, 54, Graphics.FONT_NUMBER_HOT, "--", Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                var distanceText = courses.displayDistance(distance).toString();
                var distanceFont = Graphics.FONT_NUMBER_HOT;
                if (dc.getTextWidthInPixels(distanceText, distanceFont) > 132) {
                    distanceFont = Graphics.FONT_NUMBER_MILD;
                }
                dc.drawText(center, 54, distanceFont, distanceText, Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.drawText(center, 89, Graphics.FONT_XTINY, courses.unitLabel(), Graphics.TEXT_JUSTIFY_CENTER);
            if (status != null) {
                drawFitted(dc, center, 100, status, 128);
            } else {
                var length = courses.holeLength(round.hole);
                drawFitted(dc, center, 100, length == null ? "DISTANCIA APROXIMADA" :
                    "HOYO " + courses.displayDistance(length).toString() + " " + courses.unitLabel(), 128);
            }
        }

        dc.drawLine(center - 52, 112, center + 52, 112);
        dc.drawText(center / 2, 118, Graphics.FONT_XTINY, "GOLPES", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center + center / 2, 118, Graphics.FONT_XTINY, "TOTAL", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center / 2, 136, Graphics.FONT_NUMBER_MILD, round.scores[round.hole].toString(),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center + center / 2, 136, Graphics.FONT_NUMBER_MILD, round.total().toString(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawCelebration(dc, center) {
        var title = celebration == :eagle ? "EAGLE!" : celebration == :birdie ? "BIRDIE!" :
            celebration == :par ? "PAR!" : celebration == :bogey ? "BOGEY" :
            celebration == :doubleBogey ? "DOUBLE BOGEY" : "TRIPLE BOGEY";
        dc.drawText(center, 18, Graphics.FONT_XTINY, "HOYO " + celebrationHole.toString() + " TERMINADO",
            Graphics.TEXT_JUSTIFY_CENTER);

        if (celebration == :eagle || celebration == :birdie) {
            drawBird(dc, center, celebration == :eagle);
        } else if (celebration == :par) {
            drawPar(dc, center);
        } else {
            drawBogey(dc, center, celebration == :doubleBogey ? 2 :
                celebration == :tripleBogey ? 3 : 1);
        }
        dc.drawText(center, 126, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center, 148, Graphics.FONT_XTINY, "SIGUIENTE HOYO", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawBird(dc, center, isEagle) {
        var travel = (celebrationFrame % 18) * 2 - 18;
        var x = center + travel;
        var flap = celebrationFrame % 6 < 3 ? 0 : 10;
        var wingLength = isEagle ? 35 : 27;
        var wingY = 74 + flap;
        dc.drawLine(x - wingLength, wingY, x, 57);
        dc.drawLine(x, 57, x + wingLength, wingY);
        dc.drawLine(x - wingLength + 9, wingY - 1, x - 4, 66);
        dc.drawLine(x + 4, 66, x + wingLength - 9, wingY - 1);
        dc.fillCircle(x, 70, isEagle ? 5 : 4);
        dc.drawLine(x + 4, 70, x + 11, 72);
        dc.drawLine(x - 2, 74, x - 5, 81);
        dc.drawLine(x + 2, 74, x + 5, 81);
    }

    function drawPar(dc, center) {
        var travel = (celebrationFrame % 12) * 6;
        dc.drawLine(center - 48, 94, center + 48, 94);
        dc.drawCircle(center + 30, 91, 5);
        dc.fillCircle(center - 36 + travel, 87, 4);
        dc.drawLine(center - 30, 45, center - 30, 91);
        dc.drawLine(center - 29, 46, center - 5, 54);
        dc.drawLine(center - 5, 54, center - 29, 62);
    }

    function drawBogey(dc, center, severity) {
        var bounce = celebrationFrame % 8 < 4 ? 0 : 4;
        var y = 68 + bounce;
        dc.drawCircle(center - 12, y, 15);
        dc.drawCircle(center + 8, y - 5, 19);
        dc.drawCircle(center + 25, y + 2, 12);
        dc.fillCircle(center - 6, y - 7, 2);
        dc.fillCircle(center + 12, y - 7, 2);
        dc.drawLine(center - 8, y + 6, center - 3, y + 3);
        dc.drawLine(center - 3, y + 3, center + 2, y + 6);
        dc.drawLine(center + 2, y + 6, center + 7, y + 3);
        for (var drop = 0; drop < severity; drop += 1) {
            var rainX = center - 22 + drop * 20;
            dc.drawLine(rainX, y + 20, rainX - 3, y + 27);
        }
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