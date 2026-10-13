import Toybox.Lang;

class GolfRound {
    var hole = 0;
    var holeCount = 18;
    var scores = [];
    var pars = [];
    var putts = [];
    var penalties = [];
    var completed = [];

    function initialize() {
        reset();
    }

    function reset() {
        hole = 0;
        scores = [];
        putts = [];
        penalties = [];
        completed = [];
        for (var index = 0; index < 18; index += 1) {
            scores.add(0);
            putts.add(0);
            penalties.add(0);
            completed.add(false);
            if (pars.size() < 18) {
                pars.add(null);
            }
        }
    }

    function changeScore(delta) {
        var updated = scores[hole] + delta;
        if (updated >= putts[hole] + penalties[hole] && updated <= 99) {
            scores[hole] = updated;
            completed[hole] = false;
        }
    }

    function setPar(value) {
        if (value instanceof Lang.Number && value >= 3 && value <= 6) {
            pars[hole] = value;
        }
    }

    function changePutts(delta) {
        var updated = putts[hole] + delta;
        if (updated >= 0 && updated <= scores[hole] - penalties[hole]) {
            putts[hole] = updated;
        }
    }

    function changePenalty(delta) {
        var updated = penalties[hole] + delta;
        var strokes = scores[hole] + delta;
        if (updated >= 0 && strokes <= 99 && strokes >= putts[hole] + updated) {
            penalties[hole] = updated;
            scores[hole] = strokes;
            completed[hole] = false;
        }
    }

    function finishHole() {
        if (scores[hole] == 0) {
            return false;
        }
        completed[hole] = true;
        return true;
    }

    function completedCount() {
        var count = 0;
        for (var index = 0; index < holeCount; index += 1) {
            if (completed[index]) {
                count += 1;
            }
        }
        return count;
    }

    function relativeScore() {
        var result = 0;
        var found = false;
        for (var index = 0; index < holeCount; index += 1) {
            if (completed[index]) {
                if (pars[index] == null) {
                    return null;
                }
                result += scores[index] - pars[index];
                found = true;
            }
        }
        return found ? result : null;
    }

    function statistic(values) {
        var result = 0;
        for (var index = 0; index < holeCount; index += 1) {
            result += values[index];
        }
        return result;
    }

    function changeHole(delta) {
        var updated = hole + delta;
        if (updated >= 0 && updated < holeCount) {
            hole = updated;
        }
    }

    function total() {
        var result = 0;
        for (var index = 0; index < holeCount; index += 1) {
            result += scores[index];
        }
        return result;
    }

    function restore(saved) {
        if (!(saved instanceof Lang.Dictionary)) {
            return;
        }
        var savedHole = saved["hole"];
        var savedScores = saved["scores"];
        if (!(savedHole instanceof Lang.Number) || savedHole < 0 || savedHole >= holeCount) {
            return;
        }
        if (!(savedScores instanceof Lang.Array) || savedScores.size() != 18) {
            return;
        }
        for (var index = 0; index < 18; index += 1) {
            if (!(savedScores[index] instanceof Lang.Number) || savedScores[index] < 0 || savedScores[index] > 99) {
                return;
            }
        }
        hole = savedHole;
        scores = savedScores;
        if (validExtras(saved)) {
            pars = saved["pars"];
            putts = saved["putts"];
            penalties = saved["penalties"];
            completed = saved["completed"];
        }
    }

    function validExtras(saved) {
        var keys = ["pars", "putts", "penalties", "completed"];
        for (var keyIndex = 0; keyIndex < keys.size(); keyIndex += 1) {
            var key = keys[keyIndex];
            if (!(saved[key] instanceof Lang.Array) || saved[key].size() != 18) {
                return false;
            }
        }
        for (var index = 0; index < 18; index += 1) {
            var par = saved["pars"][index];
            var putting = saved["putts"][index];
            var penalty = saved["penalties"][index];
            if ((par != null && (!(par instanceof Lang.Number) || par < 3 || par > 6)) ||
                !(putting instanceof Lang.Number) || putting < 0 ||
                !(penalty instanceof Lang.Number) || penalty < 0 ||
                putting + penalty > scores[index] || !(saved["completed"][index] instanceof Lang.Boolean) ||
                (saved["completed"][index] && scores[index] == 0)) {
                return false;
            }
        }
        return true;
    }

    function snapshot() {
        return { "hole" => hole, "scores" => scores, "pars" => pars,
            "putts" => putts, "penalties" => penalties, "completed" => completed };
    }
}