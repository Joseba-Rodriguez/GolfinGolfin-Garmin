import Toybox.Application;
import Toybox.WatchUi;

class GolfDelegate extends WatchUi.BehaviorDelegate {
    var view;
    var round;
    var courses;
    var recording;

    function initialize(golfView, golfRound, courseService, activityRecording) {
        BehaviorDelegate.initialize();
        view = golfView;
        round = golfRound;
        courses = courseService;
        recording = activityRecording;
    }

    function onSelect() {
        if (view.mode == :score || view.mode == :play || view.mode == :distance) {
            var first = round.scores[round.hole] == 0;
            round.changeScore(1);
            if (first && round.scores[round.hole] == 1) {
                courses.learnTee(round.hole);
            }
            persist();
        } else if (view.mode == :shot) {
            courses.markShot(round.hole);
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onPreviousPage() {
        if (view.mode == :score || view.mode == :play) {
            round.changeScore(-1);
            persist();
        } else if (view.mode == :distance) {
            round.changeHole(-1);
            persist();
        }
        return true;
    }

    function onNextPage() {
        if (view.mode == :play) {
            showHoleEditor();
        } else if (view.mode == :score || view.mode == :distance) {
            round.changeHole(1);
            persist();
        }
        return true;
    }

    function onBack() {
        if (view.mode != :play) {
            view.mode = round.finished ? :summary : :play;
            WatchUi.requestUpdate();
            return true;
        }
        if (recording.session != null) {
            showActivity();
            return true;
        }
        return false;
    }

    function onMenu() {
        var menu = new WatchUi.Menu2({ :title => "Golf" });
        if (courses.course == null) {
            menu.addItem(new WatchUi.MenuItem("Buscar campo cercano", "GPS + movil", :courses, null));
            menu.addItem(new WatchUi.MenuItem("Mis campos", null, :library, null));
        }
        if (!round.finished) {
            menu.addItem(new WatchUi.MenuItem("Anotar hoyo", "Hoyo " + (round.hole + 1).toString(), :editHole, null));
        }
        menu.addItem(new WatchUi.MenuItem("Tarjeta", round.total().toString() + " golpes", :card, null));
        if (!round.finished) {
            menu.addItem(new WatchUi.MenuItem("Finalizar vuelta", null, :finishRound, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Vuelta finalizada", round.total().toString() + " golpes", :summary, null));
            menu.addItem(new WatchUi.MenuItem("Nueva vuelta", null, :reset, null));
        }
        menu.addItem(new WatchUi.MenuItem("Historial", null, :history, null));
        menu.addItem(new WatchUi.MenuItem("Medir golpe", null, :shot, null));
        menu.addItem(new WatchUi.MenuItem("Actividad", recording.status, :activity, null));
        menu.addItem(new WatchUi.MenuItem("Campos", courses.course == null ? "Sin campo" : courses.course["name"], :fields, null));
        menu.addItem(new WatchUi.MenuItem("Mas opciones", null, :options, null));
        WatchUi.pushView(menu, new GolfMenuDelegate(self, false), WatchUi.SLIDE_UP);
        return true;
    }

    function showFields() {
        var menu = new WatchUi.Menu2({ :title => "Campos" });
        menu.addItem(new WatchUi.MenuItem("Buscar campo cercano", "GPS + movil", :courses, null));
        menu.addItem(new WatchUi.MenuItem("Mis campos offline", null, :library, null));
        menu.addItem(new WatchUi.MenuItem("Guardar campo offline", null, :favorite, null));
        menu.addItem(new WatchUi.MenuItem("Campo manual 9 hoyos", null, :manual9, null));
        menu.addItem(new WatchUi.MenuItem("Campo manual 18 hoyos", null, :manual18, null));
        menu.addItem(new WatchUi.MenuItem("Marcar green aqui", null, :green, null));
        if (courses.busy) {
            menu.addItem(new WatchUi.MenuItem("Cancelar descarga", null, :cancelDownload, null));
        }
        menu.addItem(new WatchUi.MenuItem("Borrar campo", null, :clearCourse, null));
        WatchUi.pushView(menu, new GolfMenuDelegate(self, false), WatchUi.SLIDE_UP);
    }

    function showOptions() {
        var menu = new WatchUi.Menu2({ :title => "Mas opciones" });
        menu.addItem(new WatchUi.MenuItem("Estadisticas / GPS", null, :status, null));
        menu.addItem(new WatchUi.MenuItem("Nueva vuelta", null, :reset, null));
        menu.addItem(new WatchUi.MenuItem("Vistas", null, :views, null));
        menu.addItem(new WatchUi.MenuItem("Unidades: " + courses.unitLabel(), null, :units, null));
        menu.addItem(new WatchUi.MenuItem(courses.gpsEnabled ? "Apagar GPS" : "Activar GPS", null, :gps, null));
        menu.addItem(new WatchUi.MenuItem("Datos / privacidad", null, :about, null));
        WatchUi.pushView(menu, new GolfMenuDelegate(self, false), WatchUi.SLIDE_UP);
    }

    function showViews() {
        var menu = new WatchUi.Menu2({ :title => "Vistas" });
        menu.addItem(new WatchUi.MenuItem("Jugar", null, :play, null));
        menu.addItem(new WatchUi.MenuItem("Puntuacion", null, :score, null));
        menu.addItem(new WatchUi.MenuItem("Distancia", null, :distance, null));
        menu.addItem(new WatchUi.MenuItem("Resumen", null, :summary, null));
        menu.addItem(new WatchUi.MenuItem("Hoyo anterior", null, :previous, null));
        menu.addItem(new WatchUi.MenuItem("Hoyo siguiente", null, :next, null));
        WatchUi.pushView(menu, new GolfMenuDelegate(self, false), WatchUi.SLIDE_UP);
    }

    function history() {
        return (Application.getApp() as GolfApp).history;
    }

    function courseName() {
        return courses.course == null ? null : courses.course["name"];
    }

    // Cierra la vuelta una sola vez y la guarda en el historial.
    function finishRound() {
        if (!round.finished) {
            round.finishRound();
            history().archive(round, courseName());
        }
    }

    function persist() {
        recording.updateFields();
        (Application.getApp() as GolfApp).saveRound();
        WatchUi.requestUpdate();
    }

    function showHoleEditor() {
        if (round.finished) {
            view.mode = :summary;
            WatchUi.requestUpdate();
            return;
        }
        var menu = new WatchUi.Menu2({ :title => "Hoyo " + (round.hole + 1).toString() });
        menu.addItem(new WatchUi.MenuItem("Cerrar hoyo", round.scores[round.hole].toString() + " golpes", :finishHole, null));
        menu.addItem(new WatchUi.MenuItem("Golpes", round.scores[round.hole].toString(), :editStrokes, null));
        menu.addItem(new WatchUi.MenuItem("Par " + (round.pars[round.hole] == null ? "--" : round.pars[round.hole].toString()),
            null, :editPar, null));
        menu.addItem(new WatchUi.MenuItem("Putts", round.putts[round.hole].toString(), :editPutts, null));
        menu.addItem(new WatchUi.MenuItem("Penalizaciones", round.penalties[round.hole].toString(), :editPenalties, null));
        WatchUi.pushView(menu, new GolfHoleDelegate(self), WatchUi.SLIDE_UP);
    }

    function showCard() {
        var menu = new WatchUi.Menu2({ :title => "Tarjeta" });
        for (var index = 0; index < round.holeCount; index += 1) {
            var par = round.pars[index] == null ? "--" : round.pars[index].toString();
            var score = round.scores[index] == 0 ? "--" : round.scores[index].toString();
            menu.addItem(new WatchUi.MenuItem("H" + (index + 1).toString() + "  PAR " + par + "  G " + score,
                round.completed[index] ? "Terminado" : "Pendiente", index, null));
        }
        WatchUi.pushView(menu, new GolfCardDelegate(self), WatchUi.SLIDE_UP);
    }

    function showActivity() {
        var menu = new WatchUi.Menu2({ :title => recording.status });
        if (!recording.active) {
            menu.addItem(new WatchUi.MenuItem(recording.session == null ? "Iniciar GPS + FIT" : "Reanudar", null, :start, null));
        }
        if (recording.session != null) {
            if (recording.active) {
                menu.addItem(new WatchUi.MenuItem("Pausar", null, :pause, null));
            }
            menu.addItem(new WatchUi.MenuItem("Finalizar y guardar", null, :save, null));
            menu.addItem(new WatchUi.MenuItem("Descartar FIT", null, :discard, null));
        }
        menu.addItem(new WatchUi.MenuItem("Tiempo", null, :time, null));
        WatchUi.pushView(menu, new GolfActivityDelegate(self, false), WatchUi.SLIDE_UP);
    }
}

class GolfMenuDelegate extends WatchUi.Menu2InputDelegate {
    var controller;
    var confirmation;

    function initialize(golfController, isConfirmation) {
        Menu2InputDelegate.initialize();
        controller = golfController;
        confirmation = isConfirmation;
    }

    function onSelect(item) {
        var identifier = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (confirmation) {
            if (identifier == :confirmReset) {
                if (controller.recording.session != null || controller.courses.busy) {
                    controller.courses.error = "Finaliza / cancela";
                    WatchUi.requestUpdate();
                    return;
                }
                if (!controller.round.finished) {
                    controller.history().archive(controller.round, controller.courseName());
                }
                controller.round.reset();
                controller.view.mode = :play;
                controller.persist();
                if (controller.courses.course != null) {
                    controller.courses.startGps();
                }
            }
            return;
        }
        if (identifier == :editHole) {
            controller.showHoleEditor();
            return;
        }
        if (identifier == :finishRound) {
            if (controller.recording.session != null) {
                controller.showActivity();
                return;
            }
            var menu = new WatchUi.Menu2({ :title => "Finalizar esta vuelta?" });
            menu.addItem(new WatchUi.MenuItem("Seguir jugando", null, :cancel, null));
            menu.addItem(new WatchUi.MenuItem("Ver resumen", null, :confirmFinishRound, null));
            WatchUi.pushView(menu, new GolfMenuDelegate(controller, false), WatchUi.SLIDE_UP);
            return;
        }
        if (identifier == :confirmFinishRound) {
            controller.finishRound();
            controller.view.mode = :summary;
            controller.persist();
            return;
        }
        if (identifier == :fields) {
            controller.showFields();
            return;
        }
        if (identifier == :options) {
            controller.showOptions();
            return;
        }
        if (identifier == :views) {
            controller.showViews();
            return;
        }
        if (identifier == :card) {
            controller.showCard();
            return;
        }
        if (identifier == :activity) {
            controller.showActivity();
            return;
        }
        if (identifier == :favorite) {
            controller.courses.keepFavorite();
            controller.persist();
            return;
        }
        if (identifier == :history) {
            controller.history().show();
            return;
        }
        if (identifier == :courses) {
            controller.courses.findNearby(controller);
            return;
        }
        if (identifier == :gps) {
            if (controller.courses.gpsEnabled) {
                controller.courses.stopGps();
            } else {
                controller.courses.startGps();
            }
            return;
        }
        if (identifier == :library) {
            controller.courses.showLibrary(controller);
            return;
        }
        if (identifier == :units) {
            controller.courses.yards = !controller.courses.yards;
            controller.persist();
            return;
        }
        if (identifier == :reset) {
            var menu = new WatchUi.Menu2({ :title => "Empezar nueva vuelta?" });
            menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
            menu.addItem(new WatchUi.MenuItem("Si, nueva vuelta", "Conservar campo", :confirmReset, null));
            WatchUi.pushView(menu, new GolfMenuDelegate(controller, true), WatchUi.SLIDE_UP);
            return;
        }
        if (identifier == :clearCourse ||
            identifier == :manual9 || identifier == :manual18 || identifier == :green) {
            var title = identifier == :green ? "Fijar green donde estoy?" :
                identifier == :manual9 || identifier == :manual18 ? "Crear campo / borrar vuelta?" : "Borrar campo y vuelta?";
            var menu = new WatchUi.Menu2({ :title => title });
            menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
            menu.addItem(new WatchUi.MenuItem("Aceptar", null, identifier, null));
            WatchUi.pushView(menu, new GolfConsentDelegate(controller), WatchUi.SLIDE_UP);
            return;
        }
        if (identifier == :cancelDownload) {
            controller.courses.cancel();
            return;
        }
        if (identifier == :about || identifier == :status) {
            var menu = new WatchUi.Menu2({ :title => identifier == :about ? "Datos abiertos" : "Campo / estado" });
            if (identifier == :about) {
                menu.addItem(new WatchUi.MenuItem("OpenStreetMap contributors", "ODbL 1.0", :info, null));
                menu.addItem(new WatchUi.MenuItem("openstreetmap.org/copyright", null, :info, null));
                menu.addItem(new WatchUi.MenuItem("Catalogo publico GitHub", "Fichas OSM estaticas", :info, null));
                menu.addItem(new WatchUi.MenuItem("Busqueda por mosaicos", "No envia GPS exacto", :info, null));
                menu.addItem(new WatchUi.MenuItem("Red publica", "Ve IP y mosaico consultado", :info, null));
                menu.addItem(new WatchUi.MenuItem("GPS aproximado", "No posicion de bandera", :info, null));
                menu.addItem(new WatchUi.MenuItem("Vuelta guardada localmente", "Sin analitica", :info, null));
                menu.addItem(new WatchUi.MenuItem("Version instalada", Rez.Strings.AppVersion, :info, null));
            } else {
                menu.addItem(new WatchUi.MenuItem(controller.courses.status, null, :info, null));
                menu.addItem(new WatchUi.MenuItem(controller.courses.course == null ? "Sin campo" :
                    controller.courses.course["name"], null, :info, null));
                var relative = controller.round.relativeScore();
                menu.addItem(new WatchUi.MenuItem("Respecto al par", relative == null ? "Sin par / hoyos" :
                    (relative > 0 ? "+" : "") + relative.toString(), :info, null));
                menu.addItem(new WatchUi.MenuItem("Putts", controller.round.statistic(controller.round.putts).toString(), :info, null));
                menu.addItem(new WatchUi.MenuItem("Penalizaciones", controller.round.statistic(controller.round.penalties).toString(), :info, null));
                menu.addItem(new WatchUi.MenuItem("Hoyos terminados", controller.round.completedCount().toString(), :info, null));
                if (controller.courses.hasFix()) {
                    var coordinates = controller.courses.location.toDegrees();
                    menu.addItem(new WatchUi.MenuItem("Latitud", coordinates[0].format("%.5f"), :info, null));
                    menu.addItem(new WatchUi.MenuItem("Longitud", coordinates[1].format("%.5f"), :info, null));
                }
            }
            WatchUi.pushView(menu, new GolfInfoDelegate(), WatchUi.SLIDE_UP);
            return;
        }
        controller.view.mode = controller.round.finished ? :summary :
            identifier == :summary ? :summary : identifier == :distance ? :distance :
            identifier == :shot ? :shot : identifier == :score ? :score : :play;
        if (identifier == :previous) {
            controller.round.changeHole(-1);
        } else if (identifier == :next) {
            controller.round.changeHole(1);
        }
        controller.persist();
    }
}

class GolfConsentDelegate extends WatchUi.Menu2InputDelegate {
    var controller;

    function initialize(golfController) {
        Menu2InputDelegate.initialize();
        controller = golfController;
    }

    function onSelect(item) {
        var identifier = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (identifier == :manual9 || identifier == :manual18) {
            controller.courses.createManual(controller, identifier == :manual9 ? 9 : 18);
        } else if (identifier == :green) {
            controller.courses.markGreen(controller.round);
            controller.persist();
        } else if (identifier == :clearCourse) {
            if (controller.recording.session != null || controller.courses.busy) {
                controller.courses.error = "Finaliza / cancela";
                WatchUi.requestUpdate();
                return;
            }
            controller.courses.clearCourse();
            controller.round.holeCount = 18;
            controller.round.reset();
            controller.courses.applyPars(controller.round, true);
            controller.view.mode = :play;
            controller.persist();
        }
    }
}

class GolfInfoDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class GolfHoleDelegate extends WatchUi.Menu2InputDelegate {
    var controller;

    function initialize(golfController) {
        Menu2InputDelegate.initialize();
        controller = golfController;
    }

    function onSelect(item) {
        var identifier = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (identifier == :editPar || identifier == :editStrokes || identifier == :editPutts || identifier == :editPenalties) {
            var round = controller.round;
            var hole = round.hole;
            var minimum = 0;
            var maximum = 99;
            var value = round.scores[hole];
            var title = "GOLPES";
            if (identifier == :editPar) {
                minimum = 3;
                maximum = 6;
                value = round.pars[hole] == null ? 4 : round.pars[hole];
                title = "PAR";
            } else if (identifier == :editPutts) {
                maximum = round.scores[hole] - round.penalties[hole];
                value = round.putts[hole];
                title = "PUTTS";
            } else if (identifier == :editPenalties) {
                maximum = 99 - round.scores[hole] + round.penalties[hole];
                value = round.penalties[hole];
                title = "PENAL";
            } else {
                minimum = round.putts[hole] + round.penalties[hole];
            }
            var editor = new GolfNumberView(title, value, minimum, maximum);
            WatchUi.pushView(editor, new GolfNumberDelegate(controller, editor, identifier, hole), WatchUi.SLIDE_UP);
            return;
        }
        if (identifier == :finishHole) {
            var result = controller.round.resultForHole(controller.round.hole);
            if (controller.round.finishHole()) {
                controller.courses.learnGreen(controller.round.hole, controller.round.pars[controller.round.hole]);
                if (result != null) {
                    controller.view.showCelebration(result, controller.round.hole + 1);
                }
                controller.round.changeHole(1);
                controller.view.mode = :play;
            } else {
                controller.courses.error = "Anota golpes";
            }
        }
        controller.persist();
    }
}

class GolfNumberDelegate extends WatchUi.BehaviorDelegate {
    var controller;
    var editor;
    var field;
    var hole;
    var course;

    function initialize(golfController, numberEditor, scoreField, holeIndex) {
        BehaviorDelegate.initialize();
        controller = golfController;
        editor = numberEditor;
        field = scoreField;
        hole = holeIndex;
        course = controller.courses.course;
    }

    function onPreviousPage() {
        editor.adjust(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() {
        editor.adjust(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onSelect() {
        if (controller.round.hole != hole || controller.courses.course != course) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        var round = controller.round;
        if (field == :editPar) {
            round.setPar(editor.value);
            var target = controller.courses.currentHole(hole);
            if (target != null) {
                target["par"] = editor.value;
            }
        } else if (field == :editStrokes) {
            round.changeScore(editor.value - round.scores[hole]);
        } else if (field == :editPutts) {
            round.changePutts(editor.value - round.putts[hole]);
        } else if (field == :editPenalties) {
            round.changePenalty(editor.value - round.penalties[hole]);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        controller.persist();
        return true;
    }
}

class GolfCardDelegate extends WatchUi.Menu2InputDelegate {
    var controller;

    function initialize(golfController) {
        Menu2InputDelegate.initialize();
        controller = golfController;
    }

    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        controller.round.hole = item.getId();
        controller.persist();
        controller.showHoleEditor();
    }
}

class GolfActivityDelegate extends WatchUi.Menu2InputDelegate {
    var controller;
    var confirmation;

    function initialize(golfController, confirming) {
        Menu2InputDelegate.initialize();
        controller = golfController;
        confirmation = confirming;
    }

    function onSelect(item) {
        var identifier = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (!confirmation && (identifier == :save || identifier == :discard)) {
            var title = identifier == :save ? "Guardar actividad?" : "Descartar actividad?";
            var menu = new WatchUi.Menu2({ :title => title });
            menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
            menu.addItem(new WatchUi.MenuItem("Aceptar", null, identifier, null));
            WatchUi.pushView(menu, new GolfActivityDelegate(controller, true), WatchUi.SLIDE_UP);
            return;
        }
        if (identifier == :start) {
            if (controller.courses.busy) {
                controller.courses.error = "Espera descarga";
            } else {
                controller.courses.startGps();
                if (controller.courses.gpsEnabled) {
                    if (controller.recording.start()) {
                        controller.view.mode = :play;
                    }
                }
            }
        } else if (identifier == :pause) {
            controller.recording.pause();
        } else if (identifier == :save) {
            var roundBeforeFinish = controller.round.snapshot();
            var wasFinished = controller.round.finished;
            controller.round.finishRound();
            if (controller.recording.save()) {
                if (!wasFinished) {
                    controller.history().archive(controller.round, controller.courseName());
                }
                controller.courses.stopGps();
                controller.view.mode = :summary;
            } else {
                controller.round.restore(roundBeforeFinish);
            }
        } else if (identifier == :discard) {
            if (controller.recording.discard()) {
                controller.courses.stopGps();
                controller.view.mode = :play;
            }
        }
        if (identifier == :time || identifier == :pause) {
            controller.view.mode = :activity;
        }
        controller.persist();
    }
}