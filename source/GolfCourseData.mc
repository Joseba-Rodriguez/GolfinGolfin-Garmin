import Toybox.Lang;
import Toybox.Math;

class GolfCourseData {
    function initialize() {
    }

    function isNumeric(value) {
        return value instanceof Lang.Number || value instanceof Lang.Long ||
            value instanceof Lang.Float || value instanceof Lang.Double;
    }

    function validPoint(point) {
        return point instanceof Lang.Dictionary && isNumeric(point["lat"]) &&
            isNumeric(point["lon"]) && point["lat"] >= -90 && point["lat"] <= 90 &&
            point["lon"] >= -180 && point["lon"] <= 180;
    }

    function validBounds(bounds) {
        return bounds instanceof Lang.Dictionary && isNumeric(bounds["minlat"]) &&
            isNumeric(bounds["minlon"]) && isNumeric(bounds["maxlat"]) &&
            isNumeric(bounds["maxlon"]) && bounds["minlat"] >= -90 &&
            bounds["maxlat"] <= 90 && bounds["minlon"] >= -180 &&
            bounds["maxlon"] <= 180 && bounds["minlat"] <= bounds["maxlat"] &&
            bounds["minlon"] <= bounds["maxlon"];
    }

    function holeNumber(reference) {
        if (!(reference instanceof Lang.String)) {
            return null;
        }
        for (var number = 1; number <= 18; number += 1) {
            if (reference.equals(number.toString())) {
                return number;
            }
        }
        return null;
    }

    function elements(data) {
        if (!(data instanceof Lang.Dictionary) || data["remark"] != null ||
            !(data["elements"] instanceof Lang.Array)) {
            return [];
        }
        return data["elements"];
    }

    function courses(data) {
        var result = [];
        var entries = elements(data);
        for (var index = 0; index < entries.size() && result.size() < 24; index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary)) {
                continue;
            }
            var tags = entry["tags"];
            var kind = entry["type"];
            var bounds = entry["bounds"];
            if (!(tags instanceof Lang.Dictionary) || !(tags["leisure"] instanceof Lang.String) ||
                !tags["leisure"].equals("golf_course") ||
                !(tags["name"] instanceof Lang.String) || tags["name"].length() == 0 ||
                !(entry["id"] instanceof Lang.Number || entry["id"] instanceof Lang.Long) ||
                entry["id"] <= 0 || !(kind instanceof Lang.String) ||
                (!kind.equals("way") && !kind.equals("relation")) ||
                !validBounds(bounds)) {
                continue;
            }
            var center = entry["center"];
            if (!validPoint(center)) {
                center = { "lat" => (bounds["minlat"] + bounds["maxlat"]) / 2.0,
                    "lon" => (bounds["minlon"] + bounds["maxlon"]) / 2.0 };
            }
            result.add({ "id" => entry["id"].toString(), "type" => kind,
                "name" => tags["name"].substring(0, tags["name"].length() > 64 ? 64 : tags["name"].length()),
                "lat" => center["lat"], "lon" => center["lon"],
                "bounds" => { "minlat" => bounds["minlat"], "minlon" => bounds["minlon"],
                    "maxlat" => bounds["maxlat"], "maxlon" => bounds["maxlon"] } });
        }
        return result;
    }

    function catalogCourses(data) {
        var result = [];
        if (!(data instanceof Lang.Dictionary) || !(data["courses"] instanceof Lang.Array)) {
            return result;
        }
        var entries = data["courses"];
        for (var index = 0; index < entries.size(); index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary) ||
                !(entry["id"] instanceof Lang.String) ||
                !(entry["type"] instanceof Lang.String) ||
                (!entry["type"].equals("way") && !entry["type"].equals("relation")) ||
                !(entry["name"] instanceof Lang.String) || entry["name"].length() == 0 ||
                entry["name"].length() > 64 || !validPoint(entry) ||
                !(entry["holes"] instanceof Lang.Number) || entry["holes"] < 0 ||
                entry["holes"] > 18 || !(entry["count"] instanceof Lang.Number) ||
                (entry["count"] != 9 && entry["count"] != 18) ||
                !(entry["file"] instanceof Lang.String) ||
                entry["file"].length() < 15 || entry["file"].length() > 64 ||
                !entry["file"].substring(0, 8).equals("courses/") ||
                !entry["file"].substring(entry["file"].length() - 5, entry["file"].length()).equals(".json")) {
                continue;
            }
            var safePath = true;
            for (var pathIndex = 0; pathIndex < entry["file"].length() - 1; pathIndex += 1) {
                if (entry["file"].substring(pathIndex, pathIndex + 2).equals("..") ||
                    (pathIndex >= 8 && entry["file"].substring(pathIndex, pathIndex + 1).equals("/")) ||
                    entry["file"].substring(pathIndex, pathIndex + 1).equals("\\")) {
                    safePath = false;
                    break;
                }
            }
            if (!safePath) {
                continue;
            }
            result.add({ "id" => entry["id"], "type" => entry["type"],
                "name" => entry["name"], "lat" => entry["lat"], "lon" => entry["lon"],
                "holes" => entry["holes"], "count" => entry["count"], "file" => entry["file"] });
        }
        return result;
    }

    function holes(data) {
        var result = [];
        for (var index = 0; index < 18; index += 1) {
            result.add(null);
        }
        var entries = elements(data);
        for (var index = 0; index < entries.size(); index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary) || !(entry["tags"] instanceof Lang.Dictionary)) {
                continue;
            }
            var tags = entry["tags"];
            var reference = tags["ref"];
            if (!(tags["golf"] instanceof Lang.String) || !tags["golf"].equals("hole") ||
                !(reference instanceof Lang.String)) {
                continue;
            }
            var number = holeNumber(reference);
            if (number == null) {
                continue;
            }
            if (result[number - 1] != null) {
                return [];
            }
            result[number - 1] = holeFromEntry(entry);
        }
        return result;
    }

    function holeForNumber(data, number) {
        var entries = elements(data);
        if (number < 1 || number > 18) {
            return null;
        }
        var selected = null;
        for (var index = 0; index < entries.size(); index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary) || !(entry["tags"] instanceof Lang.Dictionary)) {
                continue;
            }
            var tags = entry["tags"];
            if (!(tags["golf"] instanceof Lang.String) || !tags["golf"].equals("hole") ||
                holeNumber(tags["ref"]) != number) {
                continue;
            }
            var candidate = holeFromEntry(entry);
            if (candidate != null && (selected == null ||
                (selected["par"] == null && candidate["par"] != null))) {
                selected = candidate;
            }
        }
        return selected;
    }

    function holeFromEntry(entry) {
        var geometry = entry["geometry"];
        if (!(geometry instanceof Lang.Array) || geometry.size() < 2 ||
            !validPoint(geometry[0]) || !validPoint(geometry[geometry.size() - 1])) {
            return null;
        }
        var tee = geometry[0];
        var target = geometry[geometry.size() - 1];
        var tags = entry["tags"];
        var par = null;
        if (tags["par"] instanceof Lang.String) {
            var parsedPar = tags["par"].toNumber();
            if (parsedPar != null && parsedPar >= 3 && parsedPar <= 6 &&
                tags["par"].equals(parsedPar.toString())) {
                par = parsedPar;
            }
        }
        return { "lat" => target["lat"], "lon" => target["lon"], "par" => par,
            "tlat" => tee["lat"], "tlon" => tee["lon"] };
    }

    function holeNumbers(data) {
        var result = [];
        var seen = {};
        var entries = elements(data);
        for (var index = 0; index < entries.size(); index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary) || !(entry["tags"] instanceof Lang.Dictionary)) {
                continue;
            }
            var tags = entry["tags"];
            if (!(tags["golf"] instanceof Lang.String) || !tags["golf"].equals("hole") ||
                !(tags["ref"] instanceof Lang.String)) {
                continue;
            }
            var number = holeNumber(tags["ref"]);
            if (number == null) {
                continue;
            }
            seen[number] = true;
        }
        for (var number = 1; number <= 18; number += 1) {
            if (seen.hasKey(number)) {
                result.add(number);
            }
        }
        return result;
    }

    function validCachedCourse(course) {
        if (!(course instanceof Lang.Dictionary) || !(course["name"] instanceof Lang.String) ||
            course["name"].length() == 0 || course["name"].length() > 64 ||
            !(course["holes"] instanceof Lang.Array) || course["holes"].size() != 18 ||
            !(course["count"] instanceof Lang.Number) || course["count"] < 1 || course["count"] > 18) {
            return false;
        }
        var found = false;
        for (var index = 0; index < 18; index += 1) {
            var hole = course["holes"][index];
            if (hole == null) {
                continue;
            }
            if (index >= course["count"] || !validPoint(hole) ||
                (hole["par"] != null && (!(hole["par"] instanceof Lang.Number) || hole["par"] < 3 || hole["par"] > 6))) {
                return false;
            }
            found = true;
        }
        return found || (course["source"] instanceof Lang.String &&
            ((course["source"].equals("manual") && (course["count"] == 9 || course["count"] == 18)) ||
                course["source"].equals("osm")));
    }

    function distanceMeters(origin, target) {
        if (!validPoint(origin) || !validPoint(target)) {
            return null;
        }
        var originLatitude = Math.toRadians(origin["lat"].toDouble());
        var targetLatitude = Math.toRadians(target["lat"].toDouble());
        var latitudeDelta = targetLatitude - originLatitude;
        var longitudeDelta = Math.toRadians(target["lon"].toDouble() - origin["lon"].toDouble());
        var latitudeSine = Math.sin(latitudeDelta / 2.0);
        var longitudeSine = Math.sin(longitudeDelta / 2.0);
        var haversine = latitudeSine * latitudeSine + Math.cos(originLatitude) *
            Math.cos(targetLatitude) * longitudeSine * longitudeSine;
        if (haversine > 1.0) {
            haversine = 1.0;
        } else if (haversine < 0.0) {
            haversine = 0.0;
        }
        return Math.round(12742000.0d * Math.asin(Math.sqrt(haversine))).toNumber();
    }
}
