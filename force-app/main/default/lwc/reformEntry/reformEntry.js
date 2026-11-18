import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import computeForm from '@salesforce/apex/ReformApi.form';

// How long to wait after a change before asking the server again, so typing is not a request per key.
const RECOMPUTE_DELAY = 350;

const INPUT_TYPES = {
    DATE: 'date',
    DATETIME: 'datetime',
    TIME: 'time',
    EMAIL: 'email',
    PHONE: 'tel',
    URL: 'url',
    CURRENCY: 'number',
    DOUBLE: 'number',
    INTEGER: 'number',
    LONG: 'number',
    PERCENT: 'number'
};
const FORMATTERS = { CURRENCY: 'currency', PERCENT: 'percent-fixed' };
const STEPS = { CURRENCY: '0.01', DOUBLE: 'any', PERCENT: 'any', INTEGER: '1', LONG: '1' };
const INPUT_SELECTOR = 'lightning-input, lightning-textarea, lightning-combobox, lightning-dual-listbox, lightning-record-picker';

/**
 * A form drawn from a Reform blueprint.
 *
 * The server decides everything: which elements show, what their text says, what each field holds.
 * This component draws that, remembers what the user has changed, and asks again when a field the
 * blueprint's rules or text depend on (a "reactive" field) changes. Nothing is saved until Save.
 *
 * Fires `saved` with { recordId } after a save, and `cancel` when the user backs out.
 */
export default class ReformEntry extends LightningElement {
    /** The blueprint: a definition, { name } of a stored one, or both. */
    @api blueprint;
    /** Leave the buttons out, for a host that supplies its own and calls save(). */
    @api hideActions = false;

    view;
    busy = false;
    failure;

    // What the user has changed since the form was loaded or saved, by field API name.
    changes = {};
    loadedRecordId;
    recomputeTimer;
    // Each request gets a number; an answer to anything but the latest is dropped.
    latestRequest = 0;
    connected = false;

    /** The record to edit; leave empty for a new one. */
    @api
    get recordId() {
        return this.loadedRecordId;
    }
    set recordId(value) {
        const changed = value !== this.loadedRecordId;
        this.loadedRecordId = value;
        if (changed && this.connected) {
            this.changes = {};
            this.compute(false);
        }
    }

    connectedCallback() {
        this.connected = true;
        this.compute(false);
    }

    disconnectedCallback() {
        this.connected = false;
        window.clearTimeout(this.recomputeTimer);
    }

    /** Saves, if every input is valid. Resolves to the saved record's Id, or undefined. */
    @api
    async save() {
        const inputs = [...this.template.querySelectorAll(INPUT_SELECTOR)];
        // Every input is asked, so each shows its own message; only a plain false counts as invalid.
        const valid = inputs.reduce((soFar, input) => input.reportValidity() !== false && soFar, true);
        if (!valid) {
            return undefined;
        }
        window.clearTimeout(this.recomputeTimer);
        const saved = await this.compute(true);
        return saved ? saved.recordId : undefined;
    }

    async compute(save) {
        const request = ++this.latestRequest;
        const values = { ...this.changes };
        if (this.loadedRecordId) {
            values.Id = this.loadedRecordId;
        }
        this.busy = true;
        try {
            const view = await computeForm({ blueprint: this.blueprint, values, save });
            if (request !== this.latestRequest) {
                return undefined;
            }
            this.failure = undefined;
            this.view = view;
            if (save) {
                this.changes = {};
                this.loadedRecordId = view.recordId;
                this.dispatchEvent(new ShowToastEvent({ title: `${view.label} saved`, variant: 'success' }));
                this.dispatchEvent(new CustomEvent('saved', { detail: { recordId: view.recordId } }));
            }
            return view;
        } catch (error) {
            if (request === this.latestRequest) {
                this.failure = messageOf(error);
            }
            return undefined;
        } finally {
            if (request === this.latestRequest) {
                this.busy = false;
            }
        }
    }

    handleChange(event) {
        const { field, kind, reactive } = event.target.dataset;
        this.changes = { ...this.changes, [field]: valueFrom(event, kind) };
        if (reactive === 'true') {
            window.clearTimeout(this.recomputeTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.recomputeTimer = window.setTimeout(() => this.compute(false), RECOMPUTE_DELAY);
        }
    }

    handleSave() {
        this.save();
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    get heading() {
        if (!this.view) {
            return '';
        }
        return this.view.recordId ? `Edit ${this.view.label}` : `New ${this.view.label}`;
    }

    get showActions() {
        return !this.hideActions && !!this.view;
    }

    // Every mistake in the blueprint, for whoever maintains it.
    get problems() {
        if (!this.view) {
            return [];
        }
        const found = [...(this.view.problems || [])];
        this.view.parts.forEach((part, index) => {
            (part.problems || []).forEach((problem) => found.push(`Element ${index + 1}: ${problem}`));
        });
        return found;
    }

    get hasProblems() {
        return this.problems.length > 0;
    }

    // The parts on show, each with what the template needs to draw it.
    get parts() {
        if (!this.view) {
            return [];
        }
        return this.view.parts
            .map((part, index) => ({ part, index }))
            .filter(({ part }) => part.visible)
            .map(({ part, index }) => drawable(part, index, this.changes));
    }
}

function drawable(part, index, changes) {
    const type = part.dataType;
    const isField = part.kind === 'FIELD';
    // What the user typed stays on screen while a recompute is in flight.
    const value = isField && part.name in changes ? changes[part.name] : part.value;
    const isLookup = isField && type === 'REFERENCE' && !!part.lookupTo;
    const isPicklist = isField && type === 'PICKLIST';
    const isMultiPicklist = isField && type === 'MULTIPICKLIST';
    const isLongText = isField && type === 'TEXTAREA';
    const isCheckbox = isField && type === 'BOOLEAN';
    return {
        key: `${index}-${part.name || part.kind}`,
        cellClass: `slds-col slds-size_1-of-1 slds-medium-size_${part.width}-of-12 slds-p-bottom_small`,
        name: part.name,
        label: part.label,
        helpText: part.helpText,
        required: part.required === true,
        readOnly: part.readOnly === true,
        reactive: part.reactive === true ? 'true' : 'false',
        content: part.content,
        value: value === null || value === undefined ? '' : value,
        checked: value === true,
        selected: typeof value === 'string' && value ? value.split(';') : [],
        lookupValue: value || undefined,
        lookupTo: part.lookupTo,
        options: part.options || [],
        kind: type,
        inputType: INPUT_TYPES[type] || 'text',
        formatter: FORMATTERS[type],
        step: STEPS[type],
        isHeading: part.kind === 'HEADING',
        isRichText: part.kind === 'RICH_TEXT',
        isLookup,
        isPicklist,
        isMultiPicklist,
        isLongText,
        isCheckbox,
        isInput: isField && !isLookup && !isPicklist && !isMultiPicklist && !isLongText && !isCheckbox
    };
}

// The value a change event carries, as the server expects it for the field's type.
function valueFrom(event, kind) {
    if (kind === 'REFERENCE') {
        return event.detail.recordId || null;
    }
    if (kind === 'BOOLEAN') {
        return event.target.checked;
    }
    if (kind === 'MULTIPICKLIST') {
        return (event.detail.value || []).join(';') || null;
    }
    const raw = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    if (raw === '' || raw === null || raw === undefined) {
        return null;
    }
    return INPUT_TYPES[kind] === 'number' ? Number(raw) : raw;
}

function messageOf(error) {
    if (error && error.body && error.body.message) {
        return error.body.message;
    }
    return (error && error.message) || 'Something went wrong';
}
