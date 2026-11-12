// Dataverse Alchemist Playwright configuration. Run by Invoke-AlchemistUiTests.ps1, which sets:
//   ALCHEMIST_PROJECT_ROOT (CRM project root: folder containing .alchemist/), ALCHEMIST_UI_TESTDIR (specs),
//   ALCHEMIST_UI_SPEC (pattern), ALCHEMIST_UI_RESULTS (.alchemist/runs/<KEY>/ui-tests), ALCHEMIST_AUTH_STATE (session),
//   ALCHEMIST_CRM_URL, ALCHEMIST_ISSUE_KEY, ALCHEMIST_RECORD_PREFIX, ALCHEMIST_BROWSER_CHANNEL, ALCHEMIST_HEADED.
import { defineConfig } from '@playwright/test';
import path from 'node:path';

const project = process.env.ALCHEMIST_PROJECT_ROOT || process.cwd();
const results = process.env.ALCHEMIST_UI_RESULTS || path.join(project, '.alchemist', 'playwright', 'last-run');

export default defineConfig({
    testDir: process.env.ALCHEMIST_UI_TESTDIR || path.join(project, 'tests', 'ui'),
    testMatch: process.env.ALCHEMIST_UI_SPEC || '**/*.ui.spec.mjs',
    outputDir: path.join(results, 'artifacts'),
    timeout: 120000,
    expect: { timeout: 15000 },
    workers: 1,
    retries: 0,
    reporter: [
        ['list'],
        ['json', { outputFile: path.join(results, 'results.json') }],
        ['html', { outputFolder: path.join(results, 'html'), open: 'never' }]
    ],
    use: {
        channel: process.env.ALCHEMIST_BROWSER_CHANNEL || 'msedge',
        headless: process.env.ALCHEMIST_HEADED !== '1',
        storageState: process.env.ALCHEMIST_AUTH_STATE,
        viewport: { width: 1600, height: 1000 },
        locale: 'fr-FR',
        screenshot: 'on',
        trace: 'retain-on-failure',
        actionTimeout: 20000,
        navigationTimeout: 60000
    }
});
