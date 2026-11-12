// Playwright helpers for Dynamics 365 (Unified Interface) - Dataverse Alchemist.
// Generated specs (<testing.ui.specFolder>/<KEY>.ui.spec.mjs, in the CRM project) import test, expect and D365
// from this module, so @playwright/test is resolved from .claude/dataverse-alchemist/playwright/node_modules.
// Selectors verified on the UI: [data-id="<field>"], <field>-required-icon, <field>-locked-icon,
// <field>-error-message, tablist-<tab>, form-sectionHeader-<section>, [role=columnheader][col-id=<column>],
// sitemap-entity-<subarea>.
import { test as base, expect } from '@playwright/test';

export { expect };

const CRM_URL = (process.env.ALCHEMIST_CRM_URL || '').replace(/\/$/, '');
const RECORD_PREFIX = process.env.ALCHEMIST_RECORD_PREFIX || 'ALCHEMIST-E2E';

export class D365 {
    constructor(page, testInfo) {
        this.page = page;
        this.testInfo = testInfo;
        this.url = CRM_URL;
        this.created = [];
        this.scriptErrors = [];
        page.on('pageerror', (e) => this.scriptErrors.push(e.message));
    }

    prefix(label) { return `${RECORD_PREFIX} ${process.env.ALCHEMIST_ISSUE_KEY || ''} ${label}`.replace(/\s+/g, ' ').trim(); }

    async appId(uniqueName) {
        if (!uniqueName) { return null; }
        const res = await this.api('GET', `appmodules?$select=appmoduleid&$filter=uniquename eq '${uniqueName}'`);
        if (!res.value.length) { throw new Error(`App ${uniqueName} not found`); }
        return res.value[0].appmoduleid;
    }

    async ensureOrigin() {
        if (!this.page.url().startsWith(this.url)) {
            await this.page.goto(`${this.url}/api/data/v9.2/WhoAmI`);
        }
    }

    // Web API call with the browser session; returns the JSON (or { id } for a creation)
    async api(method, path, body) {
        await this.ensureOrigin();
        const result = await this.page.evaluate(async ({ url, method, path, body }) => {
            const r = await fetch(`${url}/api/data/v9.2/${path}`, {
                method,
                headers: { 'Accept': 'application/json', 'Content-Type': 'application/json; charset=utf-8', 'OData-Version': '4.0', 'OData-MaxVersion': '4.0', 'Prefer': 'odata.include-annotations="*"' },
                body: body ? JSON.stringify(body) : undefined
            });
            const text = await r.text();
            const entityId = (r.headers.get('OData-EntityId') || '').match(/\(([0-9a-f-]{36})\)/i);
            return { status: r.status, text, id: entityId ? entityId[1] : null };
        }, { url: this.url, method, path, body });
        if (result.status >= 400) { throw new Error(`${method} ${path} -> ${result.status} ${result.text.slice(0, 300)}`); }
        if (result.id) { return { id: result.id }; }
        return result.text ? JSON.parse(result.text) : {};
    }

    // Creates a test record (deleted by cleanup)
    async createRecord(entitySet, body) {
        const { id } = await this.api('POST', entitySet, body);
        this.created.push({ entitySet, id });
        return id;
    }

    // Record created from the UI: to delete at the end of the test
    track(entitySet, id) { if (id) { this.created.push({ entitySet, id }); } }

    async cleanup() {
        for (const r of this.created.reverse()) {
            try { await this.api('DELETE', `${r.entitySet}(${r.id})`); } catch (e) { console.warn(`Cleanup ${r.entitySet}(${r.id}): ${e.message}`); }
        }
        this.created = [];
    }

    // Opens a form (new record if no id) and waits for Xrm to be ready
    async openForm({ app, table, id, formId }) {
        const appid = await this.appId(app);
        const qs = new URLSearchParams({ pagetype: 'entityrecord', etn: table });
        if (appid) { qs.set('appid', appid); }
        if (id) { qs.set('id', id); }
        if (formId) { qs.set('formid', formId); }
        await this.page.goto(`${this.url}/main.aspx?${qs}`);
        await this.page.waitForFunction((etn) => window.Xrm?.Page?.data?.entity?.getEntityName?.() === etn && !!window.Xrm.Page.ui?.formSelector, table, { timeout: 60000 });
        await this.page.locator('[data-id="editFormRoot"]').waitFor({ timeout: 30000 });
        // No 'networkidle': D365 keeps requests running continuously (pointless 60 s wait)
        await this.page.waitForFunction(() => !document.querySelector('[data-id="form-loading"], .progressDotContainer'), null, { timeout: 15000 }).catch(() => {});
        await this.page.waitForTimeout(1500);
    }

    async currentFormId() { return this.page.evaluate(() => Xrm.Page.ui.formSelector.getCurrentItem()?.getId()?.replace(/[{}]/g, '').toLowerCase()); }

    field(name) { return this.page.locator(`[data-id="${name}"]`).first(); }
    requiredIcon(name) { return this.page.locator(`[data-id="${name}-required-icon"]`); }
    lockedIcon(name) { return this.page.locator(`[data-id="${name}-locked-icon"]`); }
    errorMessage(name) { return this.page.locator(`[data-id="${name}-error-message"]`); }
    tab(name) { return this.page.locator(`[data-id="tablist-${name}"]`); }
    section(name) { return this.page.locator(`[data-id="form-sectionHeader-${name}"]`); }

    async selectTab(name) {
        await this.page.evaluate((n) => Xrm.Page.ui.tabs.get(n)?.setFocus(), name);
    }

    // Value through Xrm, then fires the onChange handlers
    async setValue(name, value) {
        await this.page.evaluate(({ name, value }) => {
            const attr = Xrm.Page.getAttribute(name);
            if (!attr) { throw new Error(`Attribute ${name} is not on the form`); }
            let v = value;
            if (value && typeof value === 'object' && value.__date) { v = new Date(value.__date); }
            attr.setValue(v);
            attr.fireOnChange();
        }, { name, value: value instanceof Date ? { __date: value.toISOString() } : value });
    }

    // Choice by label (case-insensitive), then onChange
    async setOption(name, label) {
        await this.page.evaluate(({ name, label }) => {
            const attr = Xrm.Page.getAttribute(name);
            const opt = attr.getOptions().find((o) => o.text.toLowerCase() === label.toLowerCase());
            if (!opt) { throw new Error(`Option "${label}" not found in ${name}: ${attr.getOptions().map((o) => o.text).join(', ')}`); }
            attr.setValue(opt.value);
            attr.fireOnChange();
        }, { name, label });
    }

    // Choice made like a user, in the form drop-down
    async selectOption(name, label) {
        const select = this.page.locator(`[data-id="${name}.fieldControl-option-set-select"]`);
        await select.click();
        await this.page.locator('[role="option"]', { hasText: label }).first().click();
        await this.page.keyboard.press('Tab');
    }

    async getOptionText(name) { return this.page.evaluate((n) => Xrm.Page.getAttribute(n)?.getText() ?? null, name); }

    // Recherche (lookup) : { id, name, entityType }
    async setLookup(name, ref) {
        await this.page.evaluate(({ name, ref }) => {
            const attr = Xrm.Page.getAttribute(name);
            attr.setValue([{ id: ref.id, name: ref.name, entityType: ref.entityType }]);
            attr.fireOnChange();
        }, { name, ref });
    }

    // Closes the error dialog if any (plugin error, duplicate) and returns its text
    async dismissErrorDialog() {
        const dialog = this.page.locator('[data-id="errorDialogdialog"], [role="dialog"][aria-label*="rror"], [role="alertdialog"]').first();
        if (!(await dialog.isVisible().catch(() => false))) { return null; }
        const text = (await dialog.innerText()).trim();
        const ok = dialog.locator('button[data-id="errorOkButton"], button:has-text("OK"), button:has-text("Ok")').first();
        if (await ok.isVisible().catch(() => false)) { await ok.click(); }
        return text;
    }

    // Value shown on screen (input, drop-down or text), not the Xrm value
    async displayedValue(name) {
        return this.page.evaluate((n) => {
            const box = document.querySelector(`[data-id="${n}-FieldSectionItemContainer"]`);
            if (!box) { return null; }
            const input = box.querySelector('input:not([type=hidden]), select, textarea');
            if (input) { return input.tagName === 'SELECT' ? input.options[input.selectedIndex]?.text : input.value; }
            const label = box.querySelector('label');
            return box.innerText.replace(label ? label.innerText : '', '').trim();
        }, name);
    }

    async getValue(name) { return this.page.evaluate((n) => { const v = Xrm.Page.getAttribute(n)?.getValue(); return v instanceof Date ? v.toISOString() : v; }, name); }
    async isRequired(name) { return this.page.evaluate((n) => Xrm.Page.getAttribute(n)?.getRequiredLevel(), name); }
    async isVisible(name) { return this.page.evaluate((n) => Xrm.Page.getControl(n)?.getVisible() ?? null, name); }

    // Saves; returns { ok, message, dialog, id }
    async save() {
        const r = await this.page.evaluate(() => Xrm.Page.data.save().then(() => ({ ok: true }), (e) => ({ ok: false, message: e?.message || String(e) })));
        await this.page.waitForTimeout(1000);
        if (!r.ok) { r.dialog = await this.dismissErrorDialog(); }
        if (r.ok) {
            const id = await this.page.evaluate(() => Xrm.Page.data.entity.getId().replace(/[{}]/g, '').toLowerCase());
            return { ...r, id };
        }
        return r;
    }

    // Opens a view; viewColumns() returns the displayed columns (col-id) in order
    async openView({ app, table, viewId }) {
        const appid = await this.appId(app);
        const qs = new URLSearchParams({ pagetype: 'entitylist', etn: table, viewid: viewId, viewType: '1039' });
        if (appid) { qs.set('appid', appid); }
        await this.page.goto(`${this.url}/main.aspx?${qs}`);
        await this.page.locator('[data-id="grid-container"], [data-id="GridRoot"]').first().waitFor({ timeout: 60000 });
        await this.page.locator('[role="columnheader"][col-id]').nth(1).waitFor({ timeout: 30000 });
    }

    async viewColumns() {
        return this.page.$$eval('[role="columnheader"][col-id]', (els) => els.map((e) => e.getAttribute('col-id')).filter((c) => c && !c.startsWith('__')));
    }

    viewSelector(viewId) { return this.page.locator(`[data-id="ViewSelector_${viewId}"]`); }

    gridRow(text) { return this.page.locator('[role="row"]', { hasText: text }); }

    // Opens the app; sitemapEntry() returns the locator of a sitemap entry
    async openApp(app) {
        const appid = await this.appId(app);
        await this.page.goto(`${this.url}/main.aspx?appid=${appid}`);
        await this.page.locator('[data-id^="sitemap-entity-"]').first().waitFor({ timeout: 60000 });
    }

    sitemapEntry(subAreaId) { return this.page.locator(`[data-id="sitemap-entity-${subAreaId}"]`); }

    async screenshot(name) {
        const file = this.testInfo.outputPath(`${name}.png`);
        await this.page.screenshot({ path: file, fullPage: false });
        await this.testInfo.attach(name, { path: file, contentType: 'image/png' });
    }
}

export const test = base.extend({
    d365: async ({ page }, use, testInfo) => {
        const d = new D365(page, testInfo);
        await use(d);
        await d.cleanup();
    }
});
