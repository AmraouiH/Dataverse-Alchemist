/**
  * Unit tests of account.ribbon.js (node:test, no dependency).
  * Run: node --test webresources/rhz_/js/account.ribbon.test.js
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function loadRibbon(xrm) {
    // As in a browser: window is the global object (var Alchemist becomes window.Alchemist).
    const context = { Xrm: xrm, Promise: Promise };
    context.window = context;
    const source = fs.readFileSync(path.join(__dirname, "account.ribbon.js"), "utf8");
    vm.runInNewContext(source, context, { filename: "account.ribbon.js" });
    return context.window.Alchemist.Account.Ribbon;
}

function formContext(attributes) {
    return {
        getAttribute: (name) => (name in attributes ? { getValue: () => attributes[name], addOnChange: () => {} } : null),
        ui: { refreshRibbon: () => {} }
    };
}

test("hasLegalRep returns false when Legal Rep is empty", () => {
    const ribbon = loadRibbon({});
    assert.equal(ribbon.hasLegalRep(formContext({ rhz_legalrepid: null })), false);
});

test("hasLegalRep returns false when the attribute is missing from the form", () => {
    const ribbon = loadRibbon({});
    assert.equal(ribbon.hasLegalRep(formContext({})), false);
});

test("hasLegalRep returns true when Legal Rep is filled in", () => {
    const ribbon = loadRibbon({});
    const legalRep = [{ id: "1", name: "Dupont", entityType: "contact" }];
    assert.equal(ribbon.hasLegalRep(formContext({ rhz_legalrepid: legalRep })), true);
});

test("showLegalRep shows the representative name", async () => {
    const dialogs = [];
    const ribbon = loadRibbon({
        Navigation: {
            openAlertDialog: (options) => {
                dialogs.push(options);
                return Promise.resolve();
            }
        }
    });
    const legalRep = [{ id: "1", name: "Dupont", entityType: "contact" }];
    await ribbon.showLegalRep(formContext({ rhz_legalrepid: legalRep }));
    // Objects created in the vm context: another Object.prototype, so compare a serialized copy.
    assert.deepEqual(JSON.parse(JSON.stringify(dialogs)), [{ title: "Représentant légal", text: "Dupont" }]);
});

test("showLegalRep without a value shows nothing made up and does not crash", async () => {
    const dialogs = [];
    const ribbon = loadRibbon({
        Navigation: {
            openAlertDialog: (options) => {
                dialogs.push(options);
                return Promise.resolve();
            }
        }
    });
    await ribbon.showLegalRep(formContext({ rhz_legalrepid: null }));
    // Objects created in the vm context: another Object.prototype, so compare a serialized copy.
    assert.deepEqual(JSON.parse(JSON.stringify(dialogs)), [{ title: "Représentant légal", text: "-" }]);
});
