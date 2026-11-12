/**
  * Unit tests of account.information.js (node:test, no dependency).
  * Run: node --test webresources/rhz_/js/account.information.test.js
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const NOTIFICATION_ID = "rhz_account_creditlimit";
const MESSAGE = "La limite de crédit dépasse 100 000.";

function loadInformation() {
    // As in a browser: window is the global object (var Alchemist becomes window.Alchemist).
    const context = {};
    context.window = context;
    const source = fs.readFileSync(path.join(__dirname, "account.information.js"), "utf8");
    vm.runInNewContext(source, context, { filename: "account.information.js" });
    return context.window.Alchemist.Account.Information;
}

function executionContext(attributes, calls) {
    const formContext = {
        getAttribute: (name) => (name in attributes ? { getValue: () => attributes[name] } : null),
        ui: {
            setFormNotification: (message, level, id) => calls.push({ action: "set", message, level, id }),
            clearFormNotification: (id) => calls.push({ action: "clear", id })
        }
    };
    return { getFormContext: () => formContext };
}

test("onLoad shows the warning when creditlimit exceeds 100,000", () => {
    const calls = [];
    loadInformation().onLoad(executionContext({ creditlimit: 150000 }, calls));
    assert.deepEqual(calls, [{ action: "set", message: MESSAGE, level: "WARNING", id: NOTIFICATION_ID }]);
});

test("onLoad shows nothing when creditlimit is exactly 100,000", () => {
    const calls = [];
    loadInformation().onLoad(executionContext({ creditlimit: 100000 }, calls));
    assert.deepEqual(calls, [{ action: "clear", id: NOTIFICATION_ID }]);
});

test("onCreditLimitChange shows the warning above the threshold", () => {
    const calls = [];
    loadInformation().onCreditLimitChange(executionContext({ creditlimit: 100001 }, calls));
    assert.deepEqual(calls, [{ action: "set", message: MESSAGE, level: "WARNING", id: NOTIFICATION_ID }]);
});

test("onCreditLimitChange removes the warning when the value drops below the threshold", () => {
    const calls = [];
    loadInformation().onCreditLimitChange(executionContext({ creditlimit: 50000 }, calls));
    assert.deepEqual(calls, [{ action: "clear", id: NOTIFICATION_ID }]);
});

test("an empty value shows nothing and does not crash", () => {
    const calls = [];
    loadInformation().onCreditLimitChange(executionContext({ creditlimit: null }, calls));
    assert.deepEqual(calls, [{ action: "clear", id: NOTIFICATION_ID }]);
});

test("a creditlimit field missing from the form throws no error", () => {
    const calls = [];
    loadInformation().onLoad(executionContext({}, calls));
    assert.deepEqual(calls, [{ action: "clear", id: NOTIFICATION_ID }]);
});
