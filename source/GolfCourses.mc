import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class GolfCourses {
    // jsDelivr sirve el repo publico con Content-Type application/json; raw.githubusercontent
    // responde text/plain y Garmin Connect lo rechaza (-400) al pedir JSON.
    const STATIC_DATA_BASE_URL = "https://cdn.jsdelivr.net/gh/Joseba-Rodriguez/GolfinGolfin-Garmin@main/data/osm/spain/";
    const SEARCH_RADIUS_METERS = 20000;
    const SEARCH_RESULT_LIMIT = 12;
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
    var activeUrl = null;
    var staticRequest = false;
    var phase = null;
    var timeout;
    var gpsWatch;
    var searchTime = null;
    var searchOrigin = null;
    var draft = null;
    var numbers = [];
    var replacementFavorite = null;
    var controller = null;
    var yards = false;
    var shotStart = null;
    var shotHole = null;
    var favorites = [];
    var catalogTiles = [];
    var catalogTileIndex = 0;
    var catalogCandidates = [];

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

    function onPosition(info as Position.Info) as Void {
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
        searchOrigin = { "lat" => coordinates[0], "lon" => coordinates[1] };
        nearby = [];
        catalogCandidates = [];
        catalogTiles = catalogTilesFor(coordinates);
        catalogTileIndex = 0;
        if (catalogTiles.size() == 0 || catalogTiles.size() > 9) {
            fail("Catalogo solo Espana");
            return;
        }
        status = "Catalogo 1/" + catalogTiles.size().toString();
        requestCatalogTile();
    }

    function catalogTilesFor(coordinates) {
        var result = [];
        if (!(coordinates instanceof Lang.Array) || coordinates.size() < 2) {
            return result;
        }
        var latitude = coordinates[0].toDouble();
        var longitude = coordinates[1].toDouble();
        var latitudeDelta = SEARCH_RADIUS_METERS.toDouble() / 111320.0;
        var longitudeScale = Math.cos(Math.toRadians(latitude));
        if (longitudeScale < 0.05) {
            return result;
        }
        var longitudeDelta = SEARCH_RADIUS_METERS.toDouble() / (111320.0 * longitudeScale);
        var south = latitude - latitudeDelta;
        var north = latitude + latitudeDelta;
        var west = longitude - longitudeDelta;
        var east = longitude + longitudeDelta;
        if (south < 26.0 || north > 46.0 || west < -21.0 || east > 7.0) {
            return result;
        }
        for (var tileLat = Math.floor(south).toNumber(); tileLat <= Math.floor(north).toNumber(); tileLat += 1) {
            for (var tileLon = Math.floor(west).toNumber(); tileLon <= Math.floor(east).toNumber(); tileLon += 1) {
                result.add("tiles/lat_" + tileLat.toString() + "_lon_" + tileLon.toString() + ".json");
            }
        }
        return result;
    }

    function requestCatalogTile() {
        if (catalogTileIndex >= catalogTiles.size()) {
            nearby = closestCourses(catalogCandidates, searchOrigin);
            busy = false;
            activeUrl = null;
            staticRequest = false;
            if (nearby.size() > 0) {
                status = "Elige campo";
                error = null;
                showNearby();
            } else {
                status = "Sin campos OSM";
                error = "Sin campos en 20 km";
            }
            WatchUi.requestUpdate();
            return;
        }
        status = "Catalogo " + (catalogTileIndex + 1).toString() + "/" + catalogTiles.size().toString();
        requestStatic(STATIC_DATA_BASE_URL + catalogTiles[catalogTileIndex], :catalogTile);
    }

    function closestCourses(candidates, origin) {
        var result = [];
        var used = [];
        for (var index = 0; index < candidates.size(); index += 1) {
            used.add(false);
        }
        for (var resultIndex = 0; resultIndex < SEARCH_RESULT_LIMIT; resultIndex += 1) {
            var closestIndex = null;
            var closestDistance = SEARCH_RADIUS_METERS + 1;
            for (var candidateIndex = 0; candidateIndex < candidates.size(); candidateIndex += 1) {
                if (used[candidateIndex]) {
                    continue;
                }
                var distance = parser.distanceMeters(origin, candidates[candidateIndex]);
                if (distance != null && distance <= SEARCH_RADIUS_METERS && distance < closestDistance) {
                    closestIndex = candidateIndex;
                    closestDistance = distance;
                }
            }
            if (closestIndex == null) {
                break;
            }
            used[closestIndex] = true;
            candidates[closestIndex]["distance"] = closestDistance;
            result.add(candidates[closestIndex]);
        }
        return result;
    }

    function download(selectedCourse, replacementIndex) {
        if (controller.recording.session != null) {
            error = "Finaliza actividad";
            WatchUi.requestUpdate();
            return;
        }
        if (busy) {
            return;
        }
        if (!(selectedCourse["file"] instanceof Lang.String)) {
            error = "Campo sin ficha offline";
            WatchUi.requestUpdate();
            return;
        }
        draft = { "id" => selectedCourse["id"], "type" => selectedCourse["type"], "source" => "osm",
            "name" => selectedCourse["name"], "count" => selectedCourse["count"],
            "holes" => [] };
        replacementFavorite = replacementIndex;
        for (var index = 0; index < 18; index += 1) {
            draft["holes"].add(null);
        }
        busy = true;
        status = "Descargando campo";
        requestStatic(STATIC_DATA_BASE_URL + selectedCourse["file"], :detail);
    }

    function requestStatic(url, requestPhase) {
        staticRequest = true;
        activeUrl = url;
        phase = requestPhase;
        sendRequest();
        WatchUi.requestUpdate();
    }

    function sendRequest() {
        requestId += 1;
        var currentRequestId = requestId;
        error = null;
        timeout.start(method(:onTimeout), 30000, false);
        try {
            Communications.makeWebRequest(activeUrl, null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                :context => currentRequestId
            }, method(:onResponse));
        } catch (exception) {
            fail("Error conexion");
        }
    }

    function networkError(code) {
        if (code == -104 || code == -2) {
            return "Sin movil conectado";
        } else if (code == -300) {
            return "Movil sin respuesta";
        } else if (code == -400 || code == -401) {
            return "Respuesta no JSON";
        } else if (code == -402 || code == -403) {
            return "Respuesta muy grande";
        } else if (code == 404) {
            return "Ficha no publicada";
        } else if (code < 0) {
            return "Error red " + code.toString();
        }
        return "Error HTTP " + code.toString();
    }

    function onResponse(code as Lang.Number,
        data as Lang.Dictionary or Lang.String or Toybox.PersistedContent.Iterator or Null,
        context as Lang.Object) as Void {
        if (!busy || context != requestId) {
            return;
        }
        timeout.stop();
        if (code == 404 && phase == :catalogTile) {
            activeUrl = null;
            staticRequest = false;
            catalogTileIndex += 1;
            requestCatalogTile();
            return;
        }
        if (code != 200) {
            fail(networkError(code));
            return;
        }
        if (!(data instanceof Lang.Dictionary)) {
            fail("Catalogo JSON invalido");
            return;
        }
        activeUrl = null;
        staticRequest = false;
        if (phase == :catalogTile) {
            if (!(data["courses"] instanceof Lang.Array) ||
                !(data["license"] instanceof Lang.String) ||
                !data["license"].equals("ODbL-1.0")) {
                fail("Mosaico OSM invalido");
                return;
            }
            var tileCourses = parser.catalogCourses(data);
            for (var index = 0; index < tileCourses.size(); index += 1) {
                catalogCandidates.add(tileCourses[index]);
            }
            catalogTileIndex += 1;
            requestCatalogTile();
        } else if (phase == :detail) {
            if (!(data["id"] instanceof Lang.String) || !data["id"].equals(draft["id"]) ||
                !(data["license"] instanceof Lang.String) || !data["license"].equals("ODbL-1.0") ||
                !(data["elements"] instanceof Lang.Array)) {
                fail("Ficha OSM invalida");
                return;
            }
            numbers = parser.holeNumbers(data);
            if (numbers.size() == 0 && data["elements"].size() > 0) {
                fail("Ficha sin hoyos validos");
                return;
            }
            for (var position = 0; position < numbers.size(); position += 1) {
                var number = numbers[position];
                var holePosition = draft["count"] == 9 && number > 9 ? number - 10 : number - 1;
                if (holePosition < 0 || holePosition >= draft["count"] ||
                    !storeDownloadedHole(draft, holePosition, number, data)) {
                    fail("Error leyendo ficha");
                    return;
                }
            }
            completeDownload();
        } else {
            fail("Fase catalogo invalida");
        }
        WatchUi.requestUpdate();
    }

    function completeDownload() {
        var freshRound = new GolfRound();
        freshRound.holeCount = draft["count"];
        for (var holeIndex = 0; holeIndex < 18; holeIndex += 1) {
            if (draft["holes"][holeIndex] != null) {
                freshRound.pars[holeIndex] = draft["holes"][holeIndex]["par"];
            }
        }
        var updatedFavorites = favoritesIncluding(draft, replacementFavorite);
        if (updatedFavorites == null) {
            fail("Biblioteca llena");
            return;
        }
        try {
            Application.Storage.setValue("session-v2", { "round" => freshRound.snapshot(), "course" => draft,
                "favorites" => updatedFavorites, "yards" => yards });
        } catch (exception) {
            fail("Error guardado");
            return;
        }
        favorites = updatedFavorites;
        course = draft;
        draft = null;
        replacementFavorite = null;
        busy = false;
        status = "Campo offline y listo";
        error = null;
        controller.round.reset();
        controller.round.holeCount = course["count"];
        shotStart = null;
        applyPars(controller.round, true);
        controller.view.mode = :play;
        controller.persist();
        startGps();
    }

    function showNearby() {
        var menu = new WatchUi.Menu2({ :title => "Campos OSM" });
        for (var index = 0; index < nearby.size(); index += 1) {
            var distance = nearby[index]["distance"];
            var distanceLabel = distance < 1000 ? distance.toString() + " m" :
                Math.round(distance.toDouble() / 1000.0).toString() + " km";
            var mapped = nearby[index]["holes"];
            var courseLabel = mapped == 0 ? "sin hoyos GPS" : mapped.toString() + " hoyos GPS";
            menu.addItem(new WatchUi.MenuItem(nearby[index]["name"],
                distanceLabel + " / " + courseLabel, index, null));
        }
        WatchUi.pushView(menu, new GolfCourseMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    function favoriteIndex(name) {
        for (var index = 0; index < favorites.size(); index += 1) {
            if (favorites[index]["name"] instanceof Lang.String &&
                favorites[index]["name"].equals(name)) {
                return index;
            }
        }
        return null;
    }

    function favoriteCourseIndex(candidate) {
        if (candidate["id"] instanceof Lang.String) {
            for (var index = 0; index < favorites.size(); index += 1) {
                if (favorites[index]["id"] instanceof Lang.String &&
                    favorites[index]["id"].equals(candidate["id"])) {
                    return index;
                }
            }
            return null;
        }
        return favoriteIndex(candidate["name"]);
    }

    function favoritesIncluding(selectedCourse, replacementIndex) {
        var updated = [];
        var position = favoriteCourseIndex(selectedCourse);
        for (var index = 0; index < favorites.size(); index += 1) {
            updated.add(favorites[index]);
        }
        if (position == null) {
            if (replacementIndex instanceof Lang.Number &&
                replacementIndex >= 0 && replacementIndex < updated.size()) {
                position = replacementIndex;
            } else if (updated.size() < 3) {
                updated.add(selectedCourse);
                return updated;
            } else {
                return null;
            }
        }
        updated[position] = selectedCourse;
        return updated;
    }

    function storeDownloadedHole(courseDraft, position, number, data) {
        if (!(courseDraft["holes"] instanceof Lang.Array) || position < 0 ||
            position >= courseDraft["count"] || number < 1 || number > 18) {
            return false;
        }
        var hole = parser.holeForNumber(data, number);
        if (hole != null) {
            courseDraft["holes"][position] = hole;
        }
        return true;
    }

    function onTimeout() {
        if (pendingSearch) {
            fail("GPS agotado");
        } else {
            fail("Catalogo sin respuesta");
        }
    }

    function fail(message) {
        requestId += 1;
        timeout.stop();
        Communications.cancelAllRequests();
        activeUrl = null;
        staticRequest = false;
        phase = null;
        busy = false;
        pendingSearch = false;
        draft = null;
        numbers = [];
        catalogTiles = [];
        catalogTileIndex = 0;
        catalogCandidates = [];
        replacementFavorite = null;
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

    // Longitud aproximada tee -> green segun la linea OSM del hoyo.
    function holeLength(holeIndex) {
        var target = currentHole(holeIndex);
        if (target == null || target["tlat"] == null || target["tlon"] == null) {
            return null;
        }
        return parser.distanceMeters({ "lat" => target["tlat"], "lon" => target["tlon"] }, target);
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
        var position = favoriteCourseIndex(course);
        if (position != null) {
            favorites[position] = course;
            status = "Campo actualizado";
            error = null;
            return;
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
            menu.addItem(new WatchUi.MenuItem(favorites[index]["name"],
                favorites[index]["count"].toString() + " hoyos offline", index, null));
        }
        WatchUi.pushView(menu, new GolfLibraryDelegate(self, null), WatchUi.SLIDE_UP);
    }

    function useFavorite(index) {
        if (busy || controller.recording.session != null) {
            error = "Finaliza / cancela";
            return;
        }
        if (!(index instanceof Lang.Number) || index < 0 || index >= favorites.size()) {
            error = "Campo offline no disponible";
            WatchUi.requestUpdate();
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
        startGps();
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
        return target != null && target["source"] instanceof Lang.String && target["source"].equals("manual") ?
            "GREEN GPS " : "OSM APROX ";
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
            menu.addItem(new WatchUi.MenuItem("Cargar en partida", null, :use, null));
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
        var menu = new WatchUi.Menu2({ :title => selectedCourse["name"] });
        var distance = selectedCourse["distance"];
        var distanceLabel = distance < 1000 ? distance.toString() + " m" :
            Math.round(distance.toDouble() / 1000.0).toString() + " km";
        var mapped = selectedCourse["holes"] == 0 ? "sin GPS" :
            selectedCourse["holes"].toString() + " hoyos GPS";
        menu.addItem(new WatchUi.MenuItem("Guardar offline y jugar",
            distanceLabel + " / " + mapped, :download, null));
        menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
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
            if (service.favoriteCourseIndex(selectedCourse) != null || service.favorites.size() < 3) {
                service.download(selectedCourse, null);
            } else {
                var menu = new WatchUi.Menu2({ :title => "Biblioteca llena" });
                menu.addItem(new WatchUi.MenuItem("Cancelar", null, :cancel, null));
                for (var index = 0; index < service.favorites.size(); index += 1) {
                    menu.addItem(new WatchUi.MenuItem(service.favorites[index]["name"],
                        "Reemplazar campo offline", index, null));
                }
                WatchUi.pushView(menu, new GolfCourseReplaceDelegate(service, selectedCourse), WatchUi.SLIDE_UP);
            }
        }
    }
}

class GolfCourseReplaceDelegate extends WatchUi.Menu2InputDelegate {
    var service;
    var selectedCourse;

    function initialize(courseService, courseChoice) {
        Menu2InputDelegate.initialize();
        service = courseService;
        selectedCourse = courseChoice;
    }

    function onSelect(item) {
        var replacementIndex = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (replacementIndex instanceof Lang.Number) {
            service.download(selectedCourse, replacementIndex);
        }
    }
}