import { LightningElement, api } from 'lwc';
import listFormats from '@salesforce/apex/ImportApi.formats';
import runFormat from '@salesforce/apex/ImportApi.run';
import { partsOf, lineOf } from './csvParts';

// How many rows go to the server at a time. Each part is a transaction of its own.
const ROWS_PER_PART = 200;
const FAILURES_SHOWN = 100;
const CSV = 'data:text/csv;charset=utf-8,';

const FAILURE_COLUMNS = [
    { label: 'Row', fieldName: 'row', type: 'number', initialWidth: 90 },
    { label: 'What is wrong', fieldName: 'message', wrapText: true }
];

/**
 * Imports a CSV file through an import format: choose the format, choose the file, then check it
 * or import it. A file of any length is sent in parts, and the rows that fail can be downloaded
 * as a file to correct and send again.
 */
export default class ImportPanel extends LightningElement {
    /** API name of the one format this panel offers. Leave empty to let the person choose. */
    @api format;
    @api title = 'Import';

    formats = [];
    chosen;
    problem;

    fileName;
    source;
    file;

    running = false;
    done = 0;
    outcome;

    failureColumns = FAILURE_COLUMNS;

    async connectedCallback() {
        try {
            this.formats = await listFormats();
            if (this.format) {
                this.chosen = this.format;
                if (!this.current) {
                    this.problem = 'There is no import format named ' + this.format + ' that can run.';
                }
            } else if (this.formats.length === 1) {
                this.chosen = this.formats[0].name;
            }
        } catch (failed) {
            this.problem = messageOf(failed);
        }
    }

    // Choosing

    get choosing() {
        return !this.format && this.formats.length > 1;
    }

    get options() {
        return this.formats.map(({ name, label }) => ({ label, value: name }));
    }

    get current() {
        return this.formats.find((each) => each.name === this.chosen);
    }

    get noFormats() {
        return !this.problem && !this.format && this.formats.length === 0;
    }

    get headers() {
        return this.current && this.current.headers.length ? this.current.headers.join(', ') : null;
    }

    get templateHref() {
        return CSV + encodeURIComponent(lineOf(this.current.headers) + '\n');
    }

    get templateName() {
        return this.current.name + '.csv';
    }

    handleFormat(event) {
        this.chosen = event.detail.value;
        this.outcome = undefined;
    }

    // The file

    async handleFile(event) {
        const picked = event.target.files && event.target.files[0];
        this.outcome = undefined;
        this.problem = undefined;
        this.file = undefined;
        this.source = undefined;
        this.fileName = undefined;
        if (!picked) {
            return;
        }
        try {
            const text = await textOf(picked);
            const cut = partsOf(text, ROWS_PER_PART);
            if (!cut.header) {
                this.problem = 'That file is empty.';
                return;
            }
            this.source = text;
            this.file = cut;
            this.fileName = picked.name;
        } catch (failed) {
            this.problem = 'That file could not be read.';
        }
    }

    get fileNote() {
        return this.file ? `${this.fileName}: ${this.file.count} ${this.file.count === 1 ? 'row' : 'rows'}` : null;
    }

    get idle() {
        return this.running || !this.file || !this.current;
    }

    // Running

    get progress() {
        return this.file && this.file.count ? Math.round((this.done / this.file.count) * 100) : 0;
    }

    get progressNote() {
        return `${this.done} of ${this.file.count} rows`;
    }

    handleCheck() {
        return this.run(false);
    }

    handleImport() {
        return this.run(true);
    }

    async run(save) {
        const total = { save, rows: 0, created: 0, updated: 0, failed: 0, held: 0, failures: [], notes: [], columns: [], ignored: [], file: null };
        this.running = true;
        this.done = 0;
        this.outcome = undefined;
        this.problem = undefined;
        // A format that saves every row or none needs the whole file in one transaction.
        const cut = partsOf(this.source, this.current.allOrNothing ? Number.MAX_SAFE_INTEGER : ROWS_PER_PART);
        try {
            for (const part of cut.parts) {
                // One part at a time, in the order of the file: a later row may change what an earlier one made.
                // eslint-disable-next-line no-await-in-loop
                const result = await runFormat({
                    format: this.chosen,
                    text: [cut.header, ...part.rows].join('\n'),
                    rowsBefore: part.rowsBefore,
                    save
                });
                add(total, result);
                this.done += part.count;
            }
        } catch (failed) {
            const reached = this.done ? ` It stopped after row ${this.done} of ${this.file.count}; what came before stands.` : '';
            this.problem = messageOf(failed) + reached;
        }
        this.running = false;
        if (total.rows || !this.problem) {
            this.outcome = total;
        }
        this.dispatchEvent(new CustomEvent(save ? 'imported' : 'checked', { detail: { ...total } }));
    }

    // The outcome

    get headline() {
        const { save, rows, created, updated, failed, held } = this.outcome;
        if (rows === 0) {
            return 'The file has no rows under its header.';
        }
        if (!save) {
            return `An import would create ${created} and update ${updated}. ${failed} of ${rows} rows have something wrong.`;
        }
        if (held) {
            return `Nothing was saved: ${failed} of ${rows} rows failed, and this format saves every row or none.`;
        }
        return `Created ${created}, updated ${updated}. ${failed} of ${rows} rows failed.`;
    }

    get headlineClass() {
        return this.outcome.failed ? 'slds-text-heading_small slds-text-color_error' : 'slds-text-heading_small slds-text-color_success';
    }

    get notes() {
        const notes = [...this.outcome.notes];
        if (this.outcome.ignored.length) {
            notes.push('Columns not read: ' + this.outcome.ignored.join(', '));
        }
        if (!this.outcome.save && this.outcome.rows) {
            notes.push('A check cannot see what validation rules, triggers and duplicate rules will say.');
        }
        return notes.map((text, index) => ({ key: index, text }));
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    get readings() {
        return this.outcome.columns.map((text, index) => ({ key: index, text }));
    }

    get failuresShown() {
        return this.outcome.failures.slice(0, FAILURES_SHOWN);
    }

    get hasFailures() {
        return this.outcome.failures.length > 0;
    }

    get moreFailures() {
        const more = this.outcome.failures.length - FAILURES_SHOWN;
        return more > 0 ? `and ${more} more, all of them in the file below.` : null;
    }

    get failuresHref() {
        return CSV + encodeURIComponent(this.outcome.file);
    }

    get failuresName() {
        return (this.fileName || 'import').replace(/\.[^.]*$/, '') + '-failed.csv';
    }
}

// Adds one part's result to the running total. Each part's failures file has the header row; only the first is kept.
function add(total, result) {
    total.rows += result.rows;
    total.created += result.created;
    total.updated += result.updated;
    total.failed += result.failed;
    total.held += result.held;
    total.failures.push(...result.failures);
    total.columns = result.columns;
    total.ignored = result.ignored;
    for (const note of result.notes) {
        if (!total.notes.includes(note)) {
            total.notes.push(note);
        }
    }
    if (result.failuresCsv) {
        total.file = total.file ? total.file + '\n' + result.failuresCsv.slice(result.failuresCsv.indexOf('\n') + 1) : result.failuresCsv;
    }
}

function textOf(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsText(file);
    });
}

function messageOf(failed) {
    return (failed && failed.body && failed.body.message) || (failed && failed.message) || 'Something went wrong.';
}
