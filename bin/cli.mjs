#!/usr/bin/env node
// Dataverse Alchemist installer (npm). Same behavior as Install-DataverseAlchemist.ps1:
// - copies the agent files listed in .claude/dataverse-alchemist/installed-files.txt into <target>/.claude/
// - removes files of a previous version that are no longer part of the agent (only those of the old manifest)
// - creates .alchemist/alchemist.config.json from the minimal template if it is missing (never overwrites)
// - adds the agent's local data to the project .gitignore
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const pkgRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(pkgRoot, '.claude');
const manifestRel = 'dataverse-alchemist/installed-files.txt';
const { version } = JSON.parse(fs.readFileSync(path.join(pkgRoot, 'package.json'), 'utf8'));

const args = process.argv.slice(2);
const command = args.find((a) => !a.startsWith('-')) ?? 'help';
const dryRun = args.includes('--dry-run');
const help = `Dataverse Alchemist ${version}

Usage:
  npx dataverse-alchemist init [folder] [--dry-run]   Install or update the agent in a CRM project (default: current folder)
  npx dataverse-alchemist version                     Show the package version and the version installed in the folder

After installing, open the project in Claude Code and run /alchemist-init, then /alchemist-check.
Docs: https://www.npmjs.com/package/dataverse-alchemist`;

const readLines = (file) => fs.existsSync(file)
    ? fs.readFileSync(file, 'utf8').split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
    : [];

function init(targetArg) {
    const target = path.resolve(targetArg ?? process.cwd());
    if (!fs.existsSync(target)) { throw new Error(`Target folder not found: ${target}`); }
    if (path.resolve(target) === pkgRoot) { throw new Error('The target is the agent package itself.'); }
    const destRoot = path.join(target, '.claude');
    const files = readLines(path.join(source, manifestRel));
    const oldFiles = readLines(path.join(destRoot, manifestRel));
    const obsolete = oldFiles.filter((f) => !files.includes(f) && fs.existsSync(path.join(destRoot, f)));
    const actions = [];

    for (const rel of [...files, manifestRel]) {
        actions.push(`copy   .claude/${rel}`);
        if (!dryRun) {
            const to = path.join(destRoot, rel);
            fs.mkdirSync(path.dirname(to), { recursive: true });
            fs.copyFileSync(path.join(source, rel), to);
        }
    }
    for (const rel of obsolete) {
        actions.push(`remove .claude/${rel} (no longer in the agent)`);
        if (!dryRun) { fs.rmSync(path.join(destRoot, rel), { force: true }); }
    }

    const configPath = path.join(target, '.alchemist', 'alchemist.config.json');
    if (!fs.existsSync(configPath)) {
        actions.push('create .alchemist/alchemist.config.json (minimal template, to complete)');
        if (!dryRun) {
            fs.mkdirSync(path.dirname(configPath), { recursive: true });
            fs.copyFileSync(path.join(source, 'dataverse-alchemist', 'config', 'alchemist.config.minimal.json'), configPath);
        }
    }

    const ignore = ['.alchemist/runs/', '.alchemist/*.local.json', '.alchemist/playwright/', '.claude/dataverse-alchemist/playwright/node_modules/'];
    const gitignore = path.join(target, '.gitignore');
    const existing = readLines(gitignore);
    const missing = ignore.filter((l) => !existing.includes(l));
    if (missing.length) {
        actions.push(`.gitignore: add ${missing.join(', ')}`);
        if (!dryRun) { fs.appendFileSync(gitignore, ['', '# Dataverse Alchemist', ...missing, ''].join('\n')); }
    }

    console.log(`Dataverse Alchemist ${version} ${dryRun ? '(dry run) ' : ''}-> ${target}`);
    if (dryRun) { actions.forEach((a) => console.log(`  ${a}`)); }
    console.log(`${files.length} files ${dryRun ? 'to copy' : 'copied'}, ${obsolete.length} obsolete ${dryRun ? 'to remove' : 'removed'}.`);
    if (!dryRun) {
        console.log(`
Next steps:
  1. Open the project in Claude Code
  2. /alchemist-init   (or: pwsh .claude/dataverse-alchemist/config-ui/Start-AlchemistConfigUi.ps1)
  3. /alchemist-check
  4. /alchemist-ticket <KEY>
Requires PowerShell 7+ (pwsh) for the agent scripts.`);
    }
}

function showVersion() {
    const installed = path.join(process.cwd(), '.claude', 'dataverse-alchemist', 'VERSION');
    console.log(`package:   ${version}`);
    console.log(`installed: ${fs.existsSync(installed) ? fs.readFileSync(installed, 'utf8').trim() : '(not installed in this folder)'}`);
}

try {
    if (command === 'init') { init(args.filter((a) => !a.startsWith('-'))[1]); }
    else if (command === 'version' || args.includes('--version')) { showVersion(); }
    else { console.log(help); }
} catch (e) {
    console.error(`Error: ${e.message}`);
    process.exitCode = 1;
}
