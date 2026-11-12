// Browser tests (Playwright) of ticket CRM-412 - Dataverse Alchemist.
// Run: Invoke-AlchemistUiTests.ps1 -IssueKey CRM-412
// The generated section is rewritten by New-AlchemistUiTests.ps1; the custom section is kept.
import { test, expect } from '../../../../.claude/dataverse-alchemist/playwright/lib/d365.mjs';

const APP = 'rhz_ServiceClient';

// alchemist:auto:start
test.describe('CRM-412 - components', () => {
    test('Form rhz_equipement / Information: opens and shows its fields', async ({ d365 }) => {
        const form = {"table":"rhz_equipement","name":"Information","id":"eef4c250-4a59-4fce-88e8-0cc5791cac5b","tabs":[{"name":"tab_general","sections":[{"name":"sec_identification","header":true,"fields":[{"name":"rhz_name","required":false,"locked":false,"ticket":false},{"name":"rhz_numeroserie","required":true,"locked":false,"ticket":true},{"name":"rhz_typeequipement","required":false,"locked":false,"ticket":true}]},{"name":"sec_couverture","header":true,"fields":[{"name":"rhz_compteid","required":false,"locked":false,"ticket":true},{"name":"rhz_contratserviceid","required":false,"locked":false,"ticket":true},{"name":"rhz_datemiseenservice","required":false,"locked":false,"ticket":true},{"name":"rhz_datefingarantie","required":false,"locked":false,"ticket":true},{"name":"rhz_sousgarantie","required":false,"locked":true,"ticket":true}]}]}]};
        await d365.openForm({ app: APP, table: form.table, formId: form.id });
        expect(await d365.currentFormId(), 'form opened').toBe(form.id);
        for (const tab of form.tabs) {
            await expect(d365.tab(tab.name), `tab ${tab.name}`).toBeVisible();
            await d365.selectTab(tab.name);
            for (const section of tab.sections) {
                if (section.header) { await expect(d365.section(section.name), `section ${section.name}`).toBeVisible(); }
                for (const field of section.fields) {
                    await expect(d365.field(field.name), `field ${field.name}`).toBeVisible();
                    if (field.required) { await expect(d365.requiredIcon(field.name), `${field.name} required`).toBeVisible(); }
                    if (field.locked) { await expect(d365.lockedIcon(field.name), `${field.name} read-only`).toBeVisible(); }
                }
            }
        }
        await d365.screenshot('form');
        expect(d365.scriptErrors, 'script errors on the page').toEqual([]);
    });

    test('View rhz_equipement / Équipements sous garantie: opens with its columns', async ({ d365 }) => {
        const view = {"table":"rhz_equipement","name":"Équipements sous garantie","id":"85d6f6de-f9dd-f111-84e8-6045bda0c845","columns":["rhz_name","rhz_numeroserie","rhz_typeequipement","rhz_compteid","rhz_contratserviceid","rhz_datefingarantie"]};
        await d365.openView({ app: APP, table: view.table, viewId: view.id });
        await expect(d365.viewSelector(view.id), 'view selected').toBeVisible();
        expect(await d365.viewColumns(), 'columns shown').toEqual(view.columns);
        await d365.screenshot('view');
    });

    test('App rhz_ServiceClient: access to rhz_equipement from the sitemap', async ({ d365, page }) => {
        await d365.openApp('rhz_ServiceClient');
        const entry = d365.sitemapEntry('rhz_serviceclient_sub_rhz_equipement');
        await expect(entry, 'sitemap entry').toBeVisible();
        await entry.click();
        await expect(page).toHaveURL(/etn=rhz_equipement/);
        await expect(page.locator('[data-id="grid-container"], [data-id="GridRoot"]').first(), 'list shown').toBeVisible();
        await d365.screenshot('navigation');
    });

});
// alchemist:auto:end

// alchemist:custom:start
// Behavior scenarios (kept on regeneration): calculated 'Sous garantie' (under warranty) flag, unique serial
// number, content of the 'Équipements sous garantie' view. CRM labels and values are French.
const inDays = (n) => { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + n); return d; };
const isoDate = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

test.describe('CRM-412 - behaviors', () => {
    for (const [days, expected] of [[365, true], [-30, false]]) {
    test(`Under warranty: ${expected ? 'Oui' : 'Non'} when the warranty ends at D${days > 0 ? '+' : ''}${days}`, async ({ d365 }) => {
        {
            await d365.openForm({ app: APP, table: 'rhz_equipement' });
            await d365.setValue('rhz_name', d365.prefix(`warranty ${days}`));
            await d365.setValue('rhz_numeroserie', d365.prefix(`SN-${Date.now()}`));
            await d365.setValue('rhz_datefingarantie', inDays(days));
            const saved = await d365.save();
            expect(saved.ok, `save: ${saved.message}`).toBe(true);
            d365.track('rhz_equipements', saved.id);
            await d365.openForm({ app: APP, table: 'rhz_equipement', id: saved.id });
            expect(await d365.getValue('rhz_sousgarantie'), `warranty end at D${days >= 0 ? '+' : ''}${days}`).toBe(expected);
            await expect.poll(() => d365.displayedValue('rhz_sousgarantie'), { message: 'displayed value' }).toBe(expected ? 'Oui' : 'Non');
            await d365.screenshot(`under-warranty-${expected ? 'yes' : 'no'}`);
        }
    });
    }

    test('Unique serial number: a duplicate is refused on save', async ({ d365 }) => {
        const serial = `E2E-D-${Date.now()}`;
        await d365.createRecord('rhz_equipements', { rhz_name: d365.prefix('original'), rhz_numeroserie: serial });
        await d365.openForm({ app: APP, table: 'rhz_equipement' });
        await d365.setValue('rhz_name', d365.prefix('duplicate'));
        await d365.setValue('rhz_numeroserie', serial);
        const saved = await d365.save();
        if (saved.ok) { d365.track('rhz_equipements', saved.id); }
        expect(saved.ok, 'the duplicate must not be saved').toBe(false);
        await d365.screenshot('duplicate-refused');
    });

    test('Équipements sous garantie view: lists covered equipment, not the others', async ({ d365 }) => {
        const stamp = Date.now();
        const covered = d365.prefix(`view covered ${stamp}`);
        const expired = d365.prefix(`view expired ${stamp}`);
        await d365.createRecord('rhz_equipements', { rhz_name: covered, rhz_numeroserie: `E2E-C-${stamp}`, rhz_datefingarantie: isoDate(inDays(200)) });
        await d365.createRecord('rhz_equipements', { rhz_name: expired, rhz_numeroserie: `E2E-X-${stamp}`, rhz_datefingarantie: isoDate(inDays(-10)) });
        await d365.openView({ app: APP, table: 'rhz_equipement', viewId: '85d6f6de-f9dd-f111-84e8-6045bda0c845' });
        await expect(d365.gridRow(covered), 'equipment under warranty listed').toBeVisible();
        await expect(d365.gridRow(expired), 'equipment out of warranty not listed').toHaveCount(0);
        await d365.screenshot('view-content');
    });
});
// alchemist:custom:end

