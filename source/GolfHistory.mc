import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Ultimas rondas jugadas, guardadas aparte de la sesion para no perderlas al empezar otra vuelta.
class GolfHistory {
    const STORAGE_KEY = "history-v1";
    const LIMIT = 5;
    var rounds = [];

    function initialize() {
        var saved = null;
        try {
            saved = Application.Storage.getValue(STORAGE_KEY);
        } catch (exception) {
            saved = null;
        }
        if (saved instanceof Lang.Array) {
            for (var index = 0; index < saved.size() && rounds.size() < LIMIT; index += 1) {
                if (validEntry(saved[index])) {
                    rounds.add(saved[index]);
                }
            }
        }
    }

    function validEntry(entry) {
        return entry instanceof Lang.Dictionary && entry["name"] instanceof Lang.String &&
            entry["date"] instanceof Lang.String && entry["count"] instanceof Lang.Number &&
            entry["count"] >= 1 && entry["count"] <= 18 &&
            entry["scores"] instanceof Lang.Array && entry["scores"].size() == 18 &&
            entry["pars"] instanceof Lang.Array && entry["pars"].size() == 18 &&
            entry["putts"] instanceof Lang.Array && entry["putts"].size() == 18;
    }

    function entryFor(round, courseName, date) {
        var scores = [];
        var pars = [];
        var putts = [];
        for (var index = 0; index < 18; index += 1) {
            scores.add(round.scores[index]);
            pars.add(round.pars[index]);
            putts.add(round.putts[index]);
        }
        return { "name" => courseName == null ? "Sin campo" : courseName, "date" => date,
            "count" => round.holeCount, "scores" => scores, "pars" => pars, "putts" => putts };
    }

    // Guarda la ronda al principio de la lista; ignora rondas sin golpes.
    function archive(round, courseName) {
        if (round.total() == 0) {
            return false;
        }
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var date = info.day.format("%02d") + "/" + info.month.format("%02d") + " " +
            info.hour.format("%02d") + ":" + info.min.format("%02d");
        var updated = [entryFor(round, courseName, date)];
        for (var index = 0; index < rounds.size() && updated.size() < LIMIT; index += 1) {
            updated.add(rounds[index]);
        }
        rounds = updated;
        try {
            Application.Storage.setValue(STORAGE_KEY, rounds);
        } catch (exception) {
            return false;
        }
        return true;
    }

    function total(entry) {
        var result = 0;
        for (var index = 0; index < entry["count"]; index += 1) {
            result += entry["scores"][index];
        }
        return result;
    }

    // Diferencia con el par en hoyos jugados con par conocido, o null si no hay ninguno.
    function relative(entry) {
        var result = 0;
        var found = false;
        for (var index = 0; index < entry["count"]; index += 1) {
            if (entry["scores"][index] > 0 && entry["pars"][index] != null) {
                result += entry["scores"][index] - entry["pars"][index];
                found = true;
            }
        }
        return found ? result : null;
    }

    function relativeLabel(value) {
        return value == null ? "PAR --" : value == 0 ? "PAR" : (value > 0 ? "+" : "") + value.toString();
    }

    function show() {
        var menu = new WatchUi.Menu2({ :title => "Historial" });
        if (rounds.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("Sin rondas", "Finaliza una vuelta", :empty, null));
        }
        for (var index = 0; index < rounds.size(); index += 1) {
            var entry = rounds[index];
            menu.addItem(new WatchUi.MenuItem(entry["date"] + " " + total(entry).toString() + " (" +
                relativeLabel(relative(entry)) + ")", entry["name"], index, null));
        }
        WatchUi.pushView(menu, new GolfHistoryDelegate(self), WatchUi.SLIDE_UP);
    }

    function showRound(index) {
        var entry = rounds[index];
        var menu = new WatchUi.Menu2({ :title => entry["name"] });
        menu.addItem(new WatchUi.MenuItem("TOTAL " + total(entry).toString(),
            relativeLabel(relative(entry)) + " / " + entry["date"], :info, null));
        for (var hole = 0; hole < entry["count"]; hole += 1) {
            var par = entry["pars"][hole] == null ? "--" : entry["pars"][hole].toString();
            var score = entry["scores"][hole] == 0 ? "--" : entry["scores"][hole].toString();
            menu.addItem(new WatchUi.MenuItem("H" + (hole + 1).toString() + "  PAR " + par + "  G " + score,
                "Putts " + entry["putts"][hole].toString(), :info, null));
        }
        WatchUi.pushView(menu, new GolfInfoDelegate(), WatchUi.SLIDE_UP);
    }
}

class GolfHistoryDelegate extends WatchUi.Menu2InputDelegate {
    var history;

    function initialize(golfHistory) {
        Menu2InputDelegate.initialize();
        history = golfHistory;
    }

    function onSelect(item) {
        var identifier = item.getId();
        if (identifier instanceof Lang.Number) {
            history.showRound(identifier);
        }
    }
}
