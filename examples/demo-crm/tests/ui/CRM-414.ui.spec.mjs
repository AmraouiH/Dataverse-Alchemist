// Browser tests (Playwright) of ticket CRM-414 - Dataverse Alchemist.
// Run: Invoke-AlchemistUiTests.ps1 -IssueKey CRM-414
// The generated section is rewritten by New-AlchemistUiTests.ps1; the custom section is kept.
import { test, expect } from '../../../../.claude/dataverse-alchemist/playwright/lib/d365.mjs';

const APP = 'rhz_ServiceClient';

// alchemist:auto:start
test.describe('CRM-414 - components', () => {
    test('Form rhz_contratservice / Information: opens and shows its fields', async ({ d365 }) => {
        const form = {"table":"rhz_contratservice","name":"Information","id":"cff95526-8333-4f84-b7a6-1e9b9b768c17","tabs":[{"name":"tab_general","sections":[{"name":"sec_contract","header":true,"fields":[{"name":"rhz_name","required":false,"locked":false,"ticket":false},{"name":"rhz_compteid","required":false,"locked":false,"ticket":false},{"name":"rhz_contactprincipalid","required":false,"locked":false,"ticket":false}]},{"name":"sec_period","header":true,"fields":[{"name":"rhz_datedebut","required":false,"locked":false,"ticket":false},{"name":"rhz_datefin","required":false,"locked":false,"ticket":false},{"name":"rhz_montantannuel","required":false,"locked":false,"ticket":false}]},{"name":"sec_timeline","header":false,"fields":[]}]},{"name":"tab_terms","sections":[{"name":"sec_terms","header":true,"fields":[{"name":"rhz_conditionsparticulieres","required":false,"locked":false,"ticket":false}]}]}]};
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

});
// alchemist:auto:end

// alchemist:custom:start
// Behavior scenarios (kept on regeneration): script rhz_/js/rhz_contratservice.information.js. The message is in the CRM language (French).
const MESSAGE = 'La date de fin doit être postérieure ou égale à la date de début.';
const day = (y, m, d) => new Date(y, m - 1, d);

test.describe('CRM-414 - behaviors', () => {
    test('End date before start date: error shown, then removed when the dates are consistent again', async ({ d365 }) => {
        await d365.openForm({ app: APP, table: 'rhz_contratservice' });
        await d365.setValue('rhz_datedebut', day(2026, 6, 1));
        await d365.setValue('rhz_datefin', day(2026, 5, 1));
        await expect(d365.errorMessage('rhz_datefin'), 'error on the end date').toContainText(MESSAGE);
        await d365.screenshot('dates-inconsistent');
        await d365.setValue('rhz_datefin', day(2026, 6, 1));
        await expect(d365.errorMessage('rhz_datefin'), 'error removed (same day)').toHaveCount(0);
    });

    test('Inconsistent dates: save is blocked; consistent dates: it goes through', async ({ d365 }) => {
        await d365.openForm({ app: APP, table: 'rhz_contratservice' });
        await d365.setValue('rhz_name', d365.prefix('contract dates'));
        await d365.setValue('rhz_datedebut', day(2026, 6, 1));
        await d365.setValue('rhz_datefin', day(2026, 1, 1));
        const blocked = await d365.save();
        if (blocked.ok) { d365.track('rhz_contratservices', blocked.id); }
        expect(blocked.ok, 'save blocked').toBe(false);
        await d365.setValue('rhz_datefin', day(2027, 5, 31));
        const saved = await d365.save();
        expect(saved.ok, `save: ${saved.message}`).toBe(true);
        d365.track('rhz_contratservices', saved.id);
        await d365.screenshot('dates-consistent-saved');
    });

    test('Opening an existing inconsistent contract: error shown on load', async ({ d365 }) => {
        const id = await d365.createRecord('rhz_contratservices', { rhz_name: d365.prefix('existing contract'), rhz_datedebut: '2026-06-01', rhz_datefin: '2026-03-01' });
        await d365.openForm({ app: APP, table: 'rhz_contratservice', id });
        await expect(d365.errorMessage('rhz_datefin')).toContainText(MESSAGE);
    });
});
// alchemist:custom:end

