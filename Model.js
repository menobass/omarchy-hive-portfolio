.pragma library

// Data model for the Hive Portfolio plugin (ported from hive-pocket-buddy).
// refreshData(accounts, callback, errorCallback)
//   callback(snapshot)  snapshot = { accounts: [...], missing: [...], totals: {...}, hiveUsd, hbdUsd, fetchedAt }
//   errorCallback(message)

var NODES = ["https://api.hive.blog", "https://api.deathwing.me", "https://anyx.io", "https://api.openhive.network"]
var FIVE_DAYS = 5 * 24 * 60 * 60

function request(url, payload, onSuccess, onError) {
    var xhr = new XMLHttpRequest()
    xhr.open(payload ? "POST" : "GET", url, true)
    xhr.timeout = 15000
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status >= 200 && xhr.status < 300) {
            try { onSuccess(JSON.parse(xhr.responseText)) }
            catch (e) { onError("bad JSON from " + url) }
        } else {
            onError("HTTP " + xhr.status + " from " + url)
        }
    }
    if (payload) {
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(payload))
    } else {
        xhr.send()
    }
}

// JSON-RPC call with failover across NODES.
function rpc(method, params, onSuccess, onError) {
    var payload = { jsonrpc: "2.0", method: method, params: params, id: 1 }
    function attempt(i) {
        if (i >= NODES.length) { onError(method + " failed on all nodes"); return }
        request(NODES[i], payload, function(resp) {
            if (resp && resp.result !== undefined && !resp.error) onSuccess(resp.result)
            else attempt(i + 1)
        }, function() { attempt(i + 1) })
    }
    attempt(0)
}

function amount(a) {
    if (!a) return 0
    if (typeof a === "string") return parseFloat(a) || 0
    return (parseInt(a.amount, 10) || 0) / Math.pow(10, a.precision)
}

function manaPercent(bar, maxMana, now) {
    if (!bar || !(maxMana > 0)) return 0
    var elapsed = Math.max(0, now - (bar.last_update_time || now))
    var cur = Math.min(maxMana, (parseFloat(bar.current_mana) || 0) + maxMana * elapsed / FIVE_DAYS)
    return Math.max(0, Math.min(100, cur / maxMana * 100))
}

function hoursToFull(pct) {
    return pct >= 99.995 ? 0 : (100 - pct) / 100 * 120
}

// HIVE / HBD prices in USD: on-chain median price first, CoinGecko as fallback.
function getPrices(done) {
    rpc("condenser_api.get_current_median_history_price", [], function(p) {
        var base = amount(p.base), quote = amount(p.quote)
        if (base > 0 && quote > 0) { done({ hiveUsd: base / quote, hbdUsd: 1 }); return }
        gecko()
    }, gecko)
    function gecko() {
        request("https://api.coingecko.com/api/v3/simple/price?ids=hive,hive_dollar&vs_currencies=usd", null,
            function(j) { done({ hiveUsd: (j.hive && j.hive.usd) || 0, hbdUsd: (j.hive_dollar && j.hive_dollar.usd) || 1 }) },
            function() { done({ hiveUsd: 0, hbdUsd: 1 }) })
    }
}

function emptyTotals() {
    return { hive: 0, hbd: 0, hivePower: 0, hiveSavings: 0, hbdSavings: 0, usd: 0 }
}

function refreshData(names, callback, errorCallback) {
    var fail = errorCallback || function() {}
    if (!names || names.length === 0) { fail("no accounts configured"); return }

    rpc("condenser_api.get_accounts", [names], function(raw) {
        rpc("condenser_api.get_dynamic_global_properties", [], function(gp) {
            // RC is optional: failure just shows 0%.
            rpc("rc_api.find_rc_accounts", { accounts: names }, function(rcRes) { withRc(rcRes) },
                function() { withRc({ rc_accounts: [] }) })

            function withRc(rcRes) {
                getPrices(function(prices) { build(raw, gp, rcRes, prices) })
            }
        }, fail)
    }, fail)

    function build(raw, gp, rcRes, prices) {
        var now = Math.floor(Date.now() / 1000)
        var fund = amount(gp.total_vesting_fund_hive)
        var shares = amount(gp.total_vesting_shares)
        function vestsToHp(v) { return shares > 0 ? v * fund / shares : 0 }

        var byName = {}, rcByName = {}
        for (var i = 0; i < raw.length; i++) byName[raw[i].name] = raw[i]
        var rcList = (rcRes && rcRes.rc_accounts) || []
        for (var j = 0; j < rcList.length; j++) rcByName[rcList[j].account] = rcList[j]

        var accounts = [], missing = [], totals = emptyTotals()

        for (var k = 0; k < names.length; k++) {
            var a = byName[names[k]]
            if (!a) { missing.push(names[k]); continue }

            var own = amount(a.vesting_shares)
            var out = amount(a.delegated_vesting_shares)
            var inn = amount(a.received_vesting_shares)
            // Voting mana is sized on effective vests; account value only counts own stake.
            var effective = Math.max(0, own - out + inn)
            var vp = manaPercent(a.voting_manabar, effective * 1e6, now)

            var rc = rcByName[names[k]]
            var rcPct = rc ? manaPercent(rc.rc_manabar, parseFloat(rc.max_rc), now) : 0

            var hive = amount(a.balance), hiveSavings = amount(a.savings_balance)
            var hbd = amount(a.hbd_balance), hbdSavings = amount(a.savings_hbd_balance)
            var hp = vestsToHp(own)
            var rewardHive = amount(a.reward_hive_balance)
            var rewardHbd = amount(a.reward_hbd_balance)
            var rewardHp = amount(a.reward_vesting_hive)

            var usd = (hive + hiveSavings + hp + rewardHive + rewardHp) * prices.hiveUsd
                    + (hbd + hbdSavings + rewardHbd) * prices.hbdUsd

            accounts.push({
                name: a.name, votingPower: vp, votingFullInHours: hoursToFull(vp),
                rcPercent: rcPct, rcFullInHours: hoursToFull(rcPct),
                hive: hive, hiveSavings: hiveSavings, hbd: hbd, hbdSavings: hbdSavings,
                hivePower: hp, rewardHive: rewardHive, rewardHbd: rewardHbd, rewardHp: rewardHp,
                usd: usd
            })

            totals.hive += hive + hiveSavings
            totals.hbd += hbd + hbdSavings
            totals.hivePower += hp
            totals.hiveSavings += hiveSavings
            totals.hbdSavings += hbdSavings
            totals.usd += usd
        }

        callback({ accounts: accounts, missing: missing, totals: totals,
                   hiveUsd: prices.hiveUsd, hbdUsd: prices.hbdUsd, fetchedAt: Date.now() })
    }
}

function formatNumber(v, decimals) {
    var d = decimals === undefined ? 3 : decimals
    var s = (v || 0).toFixed(d)
    var parts = s.split(".")
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    return parts.join(".")
}

function formatUsd(v) {
    v = v || 0
    return "$" + formatNumber(v, v >= 1000 ? 0 : 2)
}

function formatDuration(hours) {
    if (hours <= 0) return "full"
    if (hours < 1) return "full in " + Math.round(hours * 60) + "m"
    if (hours < 24) return "full in " + Math.round(hours) + "h"
    return "full in " + Math.round(hours / 24) + "d"
}
