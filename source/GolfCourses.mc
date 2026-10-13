import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class GolfCourses {
    const ENDPOINT = "https://overpass.private.coffee/api/interpreter";
    var parser;
    var course = null;
    var nearby = [];
    var status = "Sin campo";
    var error = null;
    var busy = false;
    var gpsEnabled = false;
    var location = null;
    var fixTime = 0;
    var pendingSearch = false;
    var requestId = 0;
    var phase = null;
    var timeout;
    var gpsWatch;
    var searchTime = null;
    var draft = null;
    var numbers = [];
    var downloadIndex = 0;
    var controller = null;
    var yards = false;
    var shotStart = null;
    var shotHole = null;
    var favorites = [];

    function initialize() {
        parser = new GolfCourseData();
        timeout = new Timer.Timer();
        gpsWatch = new Timer.Timer();
    }

    function restore(saved) {
        if (parser.validCachedCourse(saved)) {
            course = saved;
            status = "Campo guardado";
        }
    }

    function hasFix() {
        return location != null && System.getTimer() - fixTime < 15000;
    }

    function startGps() {
        if (!gpsEnabled) {
            gpsEnabled = true;
            try {
                Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
                gpsWatch.start(method(:onGpsTick), 5000, true);
            } catch (exception) {
                gpsEnabled = false;
                fail("Error GPS");
            }
        }
        WatchUi.requestUpdate();
    }

    function stopGps() {
        gpsEnabled = false;
        location = null;
        gpsWatch.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        if (pendingSearch) {
            cancel();
        }
        WatchUi.requestUpdate();
    }

    function onGpsTick() {
        if (!hasFix()) {
            location = null;
        }
        WatchUi.requestUpdate();
    }

    function onPosition(info) {
        if (!gpsEnabled) {
            return;
        }
        if (info.position == null || info.accuracy != Position.QUALITY_GOOD) {
            location = null;
            WatchUi.requestUpdate();
            return;
        }
        location = info.position;
        fixTime = System.getTimer();
        if (pendingSearch) {
            pendingSearch = false;
            timeout.stop();
            search();
        }
        WatchUi.requestUpdate();
    }

    function findNearby(golfController) {
        if (busy) {
            return;
        }
        if (searchTime != null && System.getTimer() - searchTime < 300000) {
            if (nearby.size() > 0) {
                controller = golfController;
                showNearby();
            } else {
                status = "Espera 5 min";
                WatchUi.requestUpdate();
            }
            return;
        }
        controller = golfController;
        busy = true;
        pendingSearch = true;
        status = "Buscando GPS";
        timeout.start(method(:onTimeout), 45000, false);
        startGps();
        if (pendingSearch && hasFix()) {
            pendingSearch = false;
            timeout.stop();
            search();
        }
    }

    function search() {
        if (!hasFix()) {
            fail("Sin GPS fiable");
            return;
        }
        var coordinates = location.toDegrees();
        var around = "(around:20000," + coordinates[0].format("%.5f") + "," + coordinates[1].format("%.5f") + ")";
        phase = :search;
        searchTime = System.getTimer();
        nearby = [];
        status = "Buscando campos";
        request("[out:json][timeout:20];(way[\"leisure\"=\"golf_course\"][\"name\"]" + around +
            ";relation[\"leisure\"=\"golf_course\"][\"name\"]" + around + ";);out tags center 12;");
    }

    function areaQuery() {
        return draft["type"] + "(" + draft["id"] + ");map_to_area->.course;";
    }

    function download(selectedCourse) {
        if (controller.recording.session != null) {
            error = "Finaliza actividad";
            WatchUi.requestUpdate();
            return;
        }
        if (busy) {
            return;
        }
        draft = { "id" => selectedCourse["id"], "type" => selectedCourse["type"],
            "name" => selectedCourse["name"], "count" => 18, "holes" => [] };
        for (var index = 0; index < 18; index += 1) {
            draft["holes"].add(null);
        }
        busy = true;
        phase = :numbers;
        status = "Leyendo hoyos";
        request("[out:json][timeout:20];" + areaQuery() + "way(area.course)[\"golf\"=\"hole\"];out tags 37;");
    }

    function request(query) {
        requestId += 1;
        error = null;
        timeout.start(method(:onTimeout), 60000, false);
        try {
            Communications.makeWebRequest(ENDPOINT, { "data" => query }, {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED,
                    "User-Agent" => "GolfInstinct/0.2 (ConnectIQ; ad471e7b9ead4abdab2ebc51914d89da)" },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                :context => requestId
            }, method(:onResponse));
        } catch (exception) {
            fail("Error conexion");
        }
        WatchUi.requestUpdate();
    }

    function onResponse(code, data, context) {
        if (!busy || context != requestId) {
            return;
        }
        timeout.stop();
        if (code != 200 || !(data instanceof Lang.Dictionary) || data["remark"] != null ||
            !(data["elements"] instanceof Lang.Array)) {
            fail(code == 429 ? "API ocupada" : "Error red/API");
            return;
        }
        if (phase == :search) {
            nearby = parser.courses(data);
            busy = false;
            status = nearby.size() == 0 ? "Sin campos OSM" : "Elige campo";
            if (nearby.size() > 0) {
                showNearby();
            }
        } else if (phase == :numbers) {
            numbers = parser.holeNumbers(data);
            if (numbers.size() == 0) {
                fail("Sin hoyos unicos");
                return;
            }
            draft["count"] = numbers[numbers.size() - 1];
            downloadIndex = 0;
            downloadHole();
        } else if (phase == :hole) {
            var holes = parser.holes(data);
            var number = numbers[downloadIndex];
            if (holes.size() != 18 || holes[number - 1] == null) {
                fail("Hoyo sin datos");
                return;
            }
            draft["holes"][number - 1] = holes[number - 1];
            downloadIndex += 1;
            if (downloadIndex < numbers.size()) {
                downloadHole();
            } else {
                var freshRound = new GolfRound();
                freshRound.holeCount = draft["count"];
                for (var holeIndex = 0; holeIndex < 18; holeIndex += 1) {
                    if (draft["holes"][holeIndex] != null) {
                        freshRound.pars[holeIndex] = draft["holes"][holeIndex]["par"];
                    }
                }
                try {
                    Application.Storage.setValue("session-v2", { "round" => freshRound.snapshot(), "course" => draft,
                        "favorites" => favorites, "yards" => yards });
                } catch (exception) {
                    fail("Error guardado");
                    return;
                }
                course = draft;
                draft = null;
                busy = false;
                status = "Campo guardado";
                controller.round.reset();
                controller.round.holeCount = course["count"];
                shotStart = null;
                applyPars(controller.round, true);
                controller.view.mode = :play;
                controller.persist();
            }
        }
        WatchUi.requestUpdate();
    }

    function downloadHole() {
        phase = :hole;
        var number = numbers[downloadIndex];
        status = "Hoyo " + (downloadIndex + 1).toString() + "/" + numbers.size().toString();
        request("[out:json][timeout:20];" + areaQuery() + "way(area.course)[\"golf\"=\"hole\"][\"ref\"=\"" +
            number.toString() + "\"];out tags geom 2;");
    }

    function showNearby() {
        var menu = new WatchUi.Menu2({ :title => "Campos OSM" });
        for (var index = 0; index < nearby.size(); index += 1) {
            menu.addItem(new WatchUi.MenuItem(nearby[index]["name"], null, index, null));
        }
        WatchUi.pushView(menu, new GolfCourseMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    function onTimeout() {
        fail(pendingSearch ? "GPS agotado" : "Red agotada");
        Communications.cancelAllRequests();
    }

    function fail(message) {
        requestId += 1;
        timeout.stop();
        busy = false;
        pendingSearch = false;
        draft = null;
        numbers = [];
        status = message;
        error = message;
        WatchUi.requestUpdate();
    }

    function cancel() {
        fail("Cancelado");
        Communications.cancelAllRequests();
    }

    function close() {
        cancel();
        stopGps();
        controller = null;
    }

    function clearCourse() {
        cancel();
        stopGps();
        course = null;
        shotStart = null;
        nearby = [];
        searchTime = null;
        status = "Sin campo";
        error = null;
    }

    function currentHole(holeIndex) {
        if (course == null || holeIndex < 0 || holeIndex >= 18) {
            return null;
        }
        return course["holes"][holeIndex];
    }

    function distance(holeIndex) {
        var target = currentHole(holeIndex);
        if (!hasFix() || target == null) {
            return null;
        }
        var coordinates = location.toDegrees();
        return parser.distanceMeters({ "lat" => coordinates[0], "lon" => coordinates[1] }, target);
    }

    function applyPars(round, overwrite) {
        for (var index = 0; index < 18; index += 1) {
            var hole = currentHole(index);
            if (overwrite || round.pars[index] == null) {
                round.pars[index] = hole == null ? null : hole["par"];
            }
        }
    }

    function unitLabel() {
        return yards ? "yd" : "m";
    }

    function displayDistance(meters) {
        return yards ? (meters * 1.0936133 + 0.5).toNumber() : meters;
    }

    function markShot(holeIndex) {
        if (!hasFix()) {
            error = "Sin GPS fiable";
            return false;
        }
        var coordinates = location.toDegrees();
        shotStart = { "lat" => coordinates[0], "lon" => coordinates[1] };
        shotHole = holeIndex;
        error = null;
        return true;
    }

    function shotDistance(holeIndex) {
        if (!hasFix() || shotStart == null || shotHole != holeIndex) {
            return null;
        }
        var coordinates = location.toDegrees();
        return parser.distanceMeters(shotStart, { "lat" => coordinates[0], "lon" => coordinates[1] });
    }

    function restorePreferences(saved) {
        if (!(saved instanceof Lang.Dictionary)) {
            return;
        }
        if (saved["yards"] instanceof Lang.Boolean) {
            yards = saved["yards"];
        }
        var savedFavorites = saved["favorites"];
        if (savedFavorites instanceof Lang.Array && savedFavorites.size() <= 3) {
            for (var index = 0; index < savedFavorites.size(); index += 1) {
                if (parser.validCachedCourse(savedFavorites[index])) {
                    favorites.add(savedFavorites[index]);
                }
            }
        }
    }

    function keepFavorite() {
        if (course == null || busy) {
            error = "Sin campo listo";
            return;
        }
        for (var index = 0; index < favorites.size(); index += 1) {
            if (favorites[index]["name"] == course["name"]) {
                favorites[index] = course;
                status = "Campo actualizado";
                error = null;
                return;
            }
        }
        if (favorites.size() >= 3) {
            error = "Biblioteca llena";
            return;
        }
        favorites.add(course);
        status = "Campo en biblioteca";
        error = null;
    }

    function showLibrary(golfController) {
        controller = golfController;
        var menu = new WatchUi.Menu2({ :title => "Mis campos offline" });
        if (favorites.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("Sin campos guardados", null, :empty, null));
        }
        for (var index = 0; index < favorites.size(); index += 1) {
            menu.addItem(new WatchUi.MenuItem(favorites[index]["name"], null, index, null));
        }
        WatchUi.pushView(menu, new GolfLibraryDelegate(self, null), WatchUi.SLIDE_UP);
    }

    function useFavorite(index) {
        if (busy || controller.recording.session != null) {
            error = "Finaliza / cancela";
            return;
        }
        var choice = favorites[index];
        var freshRound = new GolfRound();
        freshRound.holeCount = choice["count"];
        for (var holeIndex = 0; holeIndex < 18; holeIndex += 1) {
            var hole = choice["holes"][holeIndex];
            freshRound.pars[holeIndex] = hole == null ? null : hole["par"];
        }
        try {
            Application.Storage.setValue("session-v2", { "round" => freshRound.snapshot(), "course" => choice,
                "favorites" => favorites, "yards" => yards });
        } catch (exception) {
            error = "Error guardado";
            return;
        }
        course = choice;
        controller.round.holeCount = choice["count"];
        controller.round.reset();
        controller.round.restore(freshRound.snapshot());
        shotStart = null;
        error = null;
        controller.view.mode = :play;
        controller.persist();
    }

    function createManual(golfController, count) {
        if (busy || golfController.recording.session != null || (count != 9 && count != 18)) {
            error = "Finaliza / cancela";
            return;
        }
        var holes = [];
        for (var index = 0; index < 18; index += 1) {
            holes.add(null);
        }
        var newCourse = { "name" => "Campo manual " + count.toString(), "count" => count,
            "source" => "manual", "holes" => holes };
        var fresh = new GolfRound();
        fresh.holeCount = count;
        try {
            Application.Storage.setValue("session-v2", { "round" => fresh.snapshot(), "course" => newCourse,
                "favorites" => favorites, "yards" => yards });
        } catch (exception) {
            error = "Error guardado";
            return;
        }
        course = newCourse;
        golfController.round.holeCount = count;
        golfController.round.reset();
        golfController.round.restore(fresh.snapshot());
        shotStart = null;
        error = null;
        status = "Campo manual";
        golfController.view.mode = :play;
        golfController.persist();
    }

    function markGreen(round) {
        if (!hasFix() || course == null || busy) {
            error = course == null ? "Crea / elige campo" : "Sin GPS fiable";
            return false;
        }
        var coordinates = location.toDegrees();
        course["holes"][round.hole] = { "lat" => coordinates[0], "lon" => coordinates[1],
            "par" => round.pars[round.hole], "source" => "manual" };
        error = null;
        return true;
    }

    function targetLabel(holeIndex) {
        var target = currentHole(holeIndex);
        return target != null && target["source"] == "manual" ? "GREEN GPS " : "OSM APROX ";
    }
}

class GolfLibraryDelegate extends WatchUi.Menu2InputDelegate {
    var service;
    var selected;

    function initialize(courseService, selectedIndex) {
        Menu2InputDelegate.initialize();
        service = courseService;
        selected = selectedIndex;
    }

    function onSelect(item) {
        var identifier = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (selected == null) {
            if (identifier == :empty) {
                return;
            }
            var menu = new WatchUi.Menu2({ :title => "Campo guardado" });
            menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
            menu.addItem(new WatchUi.MenuItem("Jugar / borrar vuelta", null, :use, null));
            menu.addItem(new WatchUi.MenuItem("Eliminar de biblioteca", null, :delete, null));
            WatchUi.pushView(menu, new GolfLibraryDelegate(service, identifier), WatchUi.SLIDE_UP);
        } else if (identifier == :use) {
            service.useFavorite(selected);
        } else if (identifier == :delete) {
            service.favorites.remove(service.favorites[selected]);
            service.controller.persist();
        }
    }
}

class GolfCourseMenuDelegate extends WatchUi.Menu2InputDelegate {
    var service;

    function initialize(courseService) {
        Menu2InputDelegate.initialize();
        service = courseService;
    }

    function onSelect(item) {
        var selectedCourse = service.nearby[item.getId()];
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var menu = new WatchUi.Menu2({ :title => "Cambiar y borrar vuelta?" });
        menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
        menu.addItem(new WatchUi.MenuItem("Descargar campo", null, :download, null));
        WatchUi.pushView(menu, new GolfCourseConfirmDelegate(service, selectedCourse), WatchUi.SLIDE_UP);
    }
}

class GolfCourseConfirmDelegate extends WatchUi.Menu2InputDelegate {
    var service;
    var selectedCourse;

    function initialize(courseService, courseChoice) {
        Menu2InputDelegate.initialize();
        service = courseService;
        selectedCourse = courseChoice;
    }

    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (item.getId() == :download) {
            service.download(selectedCourse);
        }
    }
}