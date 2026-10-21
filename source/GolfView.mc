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

    // Pantalla de juego para 166x166 monocromo. La subpantalla circular (arriba a la derecha,
    // junto al boton GPS) muestra los golpes del hoyo: ese boton suma uno.
    function drawPlayScreen(dc, center) {
        var holeNumber = round.hole + 1;
        var par = round.pars[round.hole];
        dc.drawText(12, 0, Graphics.FONT_SMALL, "HOYO " + holeNumber.toString(), Graphics.TEXT_JUSTIFY_LEFT);
        var length = courses.holeLength(round.hole);
        var info = (par == null ? "PAR -" : "PAR " + par.toString()) +
            (length == null ? "" : "  " + courses.displayDistance(length).toString() + courses.unitLabel());
        dc.drawText(12, 21, Graphics.FONT_XTINY, info, Graphics.TEXT_JUSTIFY_LEFT);
        drawGpsBars(dc, 92, 17);
        drawSubscreen(dc);
        dc.drawLine(8, 42, 108, 42);

        if (courses.course == null) {
            dc.drawText(center, 52, Graphics.FONT_MEDIUM, "SIN CAMPO", Graphics.TEXT_JUSTIFY_CENTER);
            drawFitted(dc, center, 78, courses.busy ? courses.status :
                courses.error != null ? courses.error : "MENU > Buscar campo", 140);
        } else {
            drawDistances(dc, center);
        }

        dc.drawLine(8, 112, 158, 112);
        var relative = round.relativeScore();
        dc.drawText(42, 112, Graphics.FONT_XTINY, "TOTAL", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(42, 125, Graphics.FONT_NUMBER_MILD, round.total().toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(124, 112, Graphics.FONT_XTINY, "AL PAR", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(124, 125, Graphics.FONT_NUMBER_MILD, relative == null ? "-" :
            relative == 0 ? "E" : (relative > 0 ? "+" : "") + relative.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        if (recording.active) {
            dc.fillCircle(center, 136, 3);
        }
        drawProgress(dc, center, 157);
    }

    function drawSubscreen(dc) {
        var x = 139;
        var y = 26;
        dc.drawCircle(x, y, 23);
        dc.drawText(x, y - 1, Graphics.FONT_NUMBER_MEDIUM, round.scores[round.hole].toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Distancia grande al centro; a la derecha fondo (triangulo arriba) y frente (triangulo abajo).
    function drawDistances(dc, center) {
        var target = courses.currentHole(round.hole);
        var distance = target != null ? courses.distance(round.hole) : courses.nearestGreenDistance();
        var frontBack = courses.frontBack(round.hole);
        var status = null;
        if (courses.busy) {
            status = courses.status;
        } else if (courses.error != null) {
            status = courses.error;
        } else if (!courses.gpsEnabled) {
            status = "GPS apagado (MENU)";
        } else if (!courses.hasFix()) {
            status = "Buscando GPS...";
        } else if (distance != null && distance > 9999) {
            status = "Fuera del campo";
        } else if (target == null && courses.looseGreens().size() == 0) {
            status = "Cierra hoyo en green";
        }
        var hasSides = frontBack != null && frontBack[0] != null && frontBack[1] != null &&
            frontBack[1] <= 9999;
        var mainX = hasSides ? 62 : center;
        var text = distance == null || distance > 9999 ? "--" : courses.displayDistance(distance).toString();
        var font = Graphics.FONT_NUMBER_THAI_HOT;
        if (dc.getTextWidthInPixels(text, font) > (hasSides ? 108 : 150)) {
            font = Graphics.FONT_NUMBER_HOT;
        }
        dc.drawText(mainX, 72, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (hasSides) {
            dc.drawLine(116, 56, 116, 102);
            drawTriangle(dc, 125, 66, true);
            dc.drawText(157, 66, Graphics.FONT_SMALL, courses.displayDistance(frontBack[1]).toString(),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            drawTriangle(dc, 125, 92, false);
            dc.drawText(157, 92, Graphics.FONT_SMALL, courses.displayDistance(frontBack[0]).toString(),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        var caption = status != null ? status : courses.targetLabel(round.hole) + " " + courses.unitLabel();
        drawFitted(dc, mainX, 95, caption, hasSides ? 110 : 140);
    }

    function drawTriangle(dc, x, y, up) {
        if (up) {
            dc.fillPolygon([[x - 5, y + 4], [x + 5, y + 4], [x, y - 4]]);
        } else {
            dc.fillPolygon([[x - 5, y - 4], [x + 5, y - 4], [x, y + 4]]);
        }
    }

    // Tres barras: llenas con fix fiable, contorno buscando, tachadas con GPS apagado.
    function drawGpsBars(dc, x, bottom) {
        for (var bar = 0; bar < 3; bar += 1) {
            var height = 4 + bar * 3;
            var left = x + bar * 4;
            if (courses.hasFix()) {
                dc.fillRectangle(left, bottom - height, 3, height);
            } else {
                dc.drawRectangle(left, bottom - height, 3, height);
            }
        }
        if (!courses.gpsEnabled) {
            dc.drawLine(x - 1, bottom - 11, x + 11, bottom + 1);
        }
    }

    // Un punto por hoyo: lleno terminado, anillo el actual, punto pequeno pendiente.
    function drawProgress(dc, center, y) {
        var count = round.holeCount;
        var spacing = count > 9 ? 6 : 11;
        var start = center - (count - 1) * spacing / 2;
        for (var index = 0; index < count; index += 1) {
            var x = start + index * spacing;
            if (index == round.hole) {
                dc.drawCircle(x, y, 3);
            } else if (round.completed[index]) {
                dc.fillCircle(x, y, 2);
            } else {
                dc.drawPoint(x, y);
            }
        }
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