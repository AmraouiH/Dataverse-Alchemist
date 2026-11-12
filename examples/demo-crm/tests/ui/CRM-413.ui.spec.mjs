// Browser tests (Playwright) of ticket CRM-413 - Dataverse Alchemist.
// Run: Invoke-AlchemistUiTests.ps1 -IssueKey CRM-413
// The generated section is rewritten by New-AlchemistUiTests.ps1; the custom section is kept.
import { test, expect } from '../../../../.claude/dataverse-alchemist/playwright/lib/d365.mjs';

const APP = 'rhz_ServiceClient';

// alchemist:auto:start
test.describe('CRM-413 - components', () => {
    test('Form rhz_intervention / Information: opens and shows its fields', async ({ d365 }) => {
        const form = {"table":"rhz_intervention","name":"Information","id":"0122dc4d-6990-423d-8305-24f955bde702","tabs":[{"name":"tab_general","sections":[{"name":"sec_intervention","header":true,"fields":[{"name":"rhz_name","required":false,"locked":false,"ticket":false},{"name":"rhz_equipementid","required":true,"locked":false,"ticket":true},{"name":"rhz_dateintervention","required":false,"locked":false,"ticket":true},{"name":"rhz_statutintervention","required":false,"locked":false,"ticket":true},{"name":"rhz_dureeheures","required":false,"locked":false,"ticket":true},{"name":"rhz_technicienid","required":false,"locked":false,"ticket":true}]},{"name":"sec_compterendu","header":true,"fields":[{"name":"rhz_compterendu","required":false,"locked":false,"ticket":true}]}]}]};
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

    test.skip('Field rhz_equipement.rhz_datederniereintervention: on a form', async () => {
        // Skipped: the column is on no active main form; nothing to check in the UI.
    });

});
// alchemist:auto:end

// alchemist:custom:start
// Behavior scenarios (kept on regeneration): default status, business rule 'Compte rendu
// obligatoire si réalisée', InterventionCompletionPlugin as seen from the form. CRM labels and values are French.
const DURATION_MESSAGE = 'Une intervention réalisée doit avoir une durée positive';
const day = (y, m, d) => new Date(y, m - 1, d, 10, 0, 0);

async function newIntervention(d365, equipment, label) {
    await d365.openForm({ app: APP, table: 'rhz_intervention' });
    await d365.setValue('rhz_name', d365.prefix(label));
    await d365.setLookup('rhz_equipementid', { id: equipment.id, name: equipment.name, entityType: 'rhz_equipement' });
}

test.describe('CRM-413 - behaviors', () => {
    test('Status defaults to Planifiée (planned) on a new intervention', async ({ d365 }) => {
        await d365.openForm({ app: APP, table: 'rhz_intervention' });
        expect(await d365.getOptionText('rhz_statutintervention')).toBe('Planifiée');
    });

    test('Business rule: report required when the status becomes Réalisée (done), no longer afterwards', async ({ d365 }) => {
        await d365.openForm({ app: APP, table: 'rhz_intervention' });
        expect(await d365.isRequired('rhz_compterendu'), 'status Planifiée').toBe('none');
        await d365.selectOption('rhz_statutintervention', 'Réalisée');
        await expect.poll(() => d365.isRequired('rhz_compterendu'), { message: 'status Réalisée' }).toBe('required');
        await expect(d365.requiredIcon('rhz_compterendu')).toBeVisible();
        await d365.screenshot('report-required');
        await d365.selectOption('rhz_statutintervention', 'Annulée');
        await expect.poll(() => d365.isRequired('rhz_compterendu'), { message: 'status Annulée' }).toBe('none');
    });

    test('Plugin: a completed intervention without a duration is refused with a clear message', async ({ d365 }) => {
        const name = d365.prefix('equipment no duration');
        const equipment = { id: await d365.createRecord('rhz_equipements', { rhz_name: name, rhz_numeroserie: `E2E-${Date.now()}` }), name };
        await newIntervention(d365, equipment, 'no duration');
        await d365.setValue('rhz_dateintervention', day(2026, 11, 2));
        await d365.setOption('rhz_statutintervention', 'Réalisée');
        await d365.setValue('rhz_compterendu', 'Test navigateur');
        await d365.setValue('rhz_dureeheures', 0);
        const saved = await d365.save();
        if (saved.ok) { d365.track('rhz_interventions', saved.id); }
        expect(saved.ok, 'save refused').toBe(false);
        expect(`${saved.message} ${saved.dialog}`, 'plugin message').toContain(DURATION_MESSAGE);
        await d365.screenshot('duration-refused');
    });

    test('Plugin: the equipment last intervention date moves forward, never backwards', async ({ d365 }) => {
        const name = d365.prefix('equipment date');
        const equipment = { id: await d365.createRecord('rhz_equipements', { rhz_name: name, rhz_numeroserie: `E2E-${Date.now()}` }), name };
        const lastDate = async () => (await d365.api('GET', `rhz_equipements(${equipment.id})?$select=rhz_datederniereintervention`)).rhz_datederniereintervention;

        for (const [label, date] of [['recent', day(2026, 11, 5)], ['older', day(2026, 10, 1)]]) {
            await newIntervention(d365, equipment, label);
            await d365.setValue('rhz_dateintervention', date);
            await d365.setOption('rhz_statutintervention', 'Réalisée');
            await d365.setValue('rhz_compterendu', 'Test navigateur');
            await d365.setValue('rhz_dureeheures', 1.5);
            const saved = await d365.save();
            expect(saved.ok, `intervention ${label}: ${saved.message}`).toBe(true);
            d365.track('rhz_interventions', saved.id);
        }
        const stored = await lastDate();
        expect(stored, 'last intervention date').toBeTruthy();
        expect(new Date(stored).getDate(), 'stays on Nov 5 despite the Oct 1 intervention').toBe(5);
    });
});
// alchemist:custom:end

