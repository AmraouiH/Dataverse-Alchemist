/**
  * Unit tests of rhz_contratservice.information.js (node:test, no dependency).
  * Run: node --test webresources/rhz_/js/rhz_contratservice.information.test.js
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const NOTIFICATION_ID = "rhz_contratservice_dates";
const MESSAGE = "La date de fin doit être postérieure ou égale à la date de début.";

function load() {
    // As in a browser: window is the global object (var Alchemist becomes window.Alchemist).
    const context = {};
    context.window = context;
    const source = fs.readFileSync(path.join(__dirname, "rhz_contratservice.information.js"), "utf8");
    vm.runInNewContext(source, context, { filename: "rhz_contratservice.information.js" });
    return context.window.Alchemist.ContratService.Information;
}

function executionContext(values, calls) {
    const formContext = {
        getAttribute: (name) => (name in values ? { getValue: () => values[name] } : null),
        getControl: (name) => (name === "rhz_datefin" ? {
            setNotification: (message, id) => calls.push({ action: "set", message, id }),
            clearNotification: (id) => calls.push({ action: "clear", id })
        } : null)
    };
    return {
        getFormContext: () => formContext,
        getEventArgs: () => ({ preventDefault: () => calls.push({ action: "preventDefault" }) })
    };
}

test("end before start: error on the end date", () => {
    const calls = [];
    load().onDateChange(executionContext({ rhz_datedebut: new Date(2026, 5, 10), rhz_datefin: new Date(2026, 5, 9) }, calls));
    assert.deepEqual(calls, [{ action: "set", message: MESSAGE, id: NOTIFICATION_ID }]);
});

test("end equal to start (different times): consistent, error removed", () => {
    const calls = [];
    load().onDateChange(executionContext({ rhz_datedebut: new Date(2026, 5, 10, 18, 0), rhz_datefin: new Date(2026, 5, 10, 8, 0) }, calls));
    assert.deepEqual(calls, [{ action: "clear", id: NOTIFICATION_ID }]);
});

test("an empty date: no error", () => {
    const calls = [];
    load().onLoad(executionContext({ rhz_datedebut: null, rhz_datefin: new Date(2026, 0, 1) }, calls));
    assert.deepEqual(calls, [{ action: "clear", id: NOTIFICATION_ID }]);
});

test("save blocked when the dates are inconsistent", () => {
    const calls = [];
    load().onSave(executionContext({ rhz_datedebut: new Date(2026, 5, 10), rhz_datefin: new Date(2026, 0, 1) }, calls));
    assert.deepEqual(calls.map((c) => c.action), ["set", "preventDefault"]);
});

test("save allowed when the dates are consistent", () => {
    const calls = [];
    load().onSave(executionContext({ rhz_datedebut: new Date(2026, 0, 1), rhz_datefin: new Date(2026, 11, 31) }, calls));
    assert.deepEqual(calls.map((c) => c.action), ["clear"]);
});

test("date field missing from the form: no JavaScript error", () => {
    const formContext = { getAttribute: () => null, getControl: () => null };
    assert.doesNotThrow(() => load().onLoad({ getFormContext: () => formContext }));
});
