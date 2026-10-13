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
        for (var index = 0; index < entries.size() && result.size() < 12; index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary)) {
                continue;
            }
            var tags = entry["tags"];
            var kind = entry["type"];
            if (!(tags instanceof Lang.Dictionary) || tags["leisure"] != "golf_course" ||
                !(tags["name"] instanceof Lang.String) || tags["name"].length() == 0 ||
                !(entry["id"] instanceof Lang.Number || entry["id"] instanceof Lang.Long) ||
                entry["id"] <= 0 || (kind != "way" && kind != "relation") ||
                !validPoint(entry["center"])) {
                continue;
            }
            result.add({ "id" => entry["id"].toString(), "type" => kind,
                "name" => tags["name"].substring(0, tags["name"].length() > 64 ? 64 : tags["name"].length()),
                "lat" => entry["center"]["lat"], "lon" => entry["center"]["lon"] });
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
            if (tags["golf"] != "hole" || !(reference instanceof Lang.String)) {
                continue;
            }
            var number = reference.toNumber();
            if (number == null || number < 1 || number > 18 || number.toString() != reference) {
                continue;
            }
            if (result[number - 1] != null) {
                return [];
            }
            var geometry = entry["geometry"];
            if (!(geometry instanceof Lang.Array) || geometry.size() < 2 ||
                !validPoint(geometry[0]) || !validPoint(geometry[geometry.size() - 1])) {
                continue;
            }
            var target = geometry[geometry.size() - 1];
            var par = null;
            if (tags["par"] instanceof Lang.String) {
                var parsedPar = tags["par"].toNumber();
                if (parsedPar != null && parsedPar >= 3 && parsedPar <= 6 && parsedPar.toString() == tags["par"]) {
                    par = parsedPar;
                }
            }
            result[number - 1] = { "lat" => target["lat"], "lon" => target["lon"], "par" => par };
        }
        return result;
    }

    function holeNumbers(data) {
        var result = [];
        var seen = {};
        var entries = elements(data);
        if (entries.size() > 36) {
            return [];
        }
        for (var index = 0; index < entries.size(); index += 1) {
            var entry = entries[index];
            if (!(entry instanceof Lang.Dictionary) || !(entry["tags"] instanceof Lang.Dictionary)) {
                continue;
            }
            var tags = entry["tags"];
            if (tags["golf"] != "hole" || !(tags["ref"] instanceof Lang.String)) {
                continue;
            }
            var number = tags["ref"].toNumber();
            if (number == null || number < 1 || number > 18 || number.toString() != tags["ref"]) {
                return [];
            }
            if (seen.hasKey(number)) {
                return [];
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
        return found || (course["source"] == "manual" && (course["count"] == 9 || course["count"] == 18));
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
