import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import listPage from '@salesforce/apex/ReformApi.table';
import removeRecord from '@salesforce/apex/ReformApi.remove';

const COLUMN_TYPES = {
    CURRENCY: 'currency',
    DOUBLE: 'number',
    INTEGER: 'number',
    LONG: 'number',
    PERCENT: 'percent',
    BOOLEAN: 'boolean',
    DATE: 'date-local',
    DATETIME: 'date',
    EMAIL: 'email',
    PHONE: 'phone',
    URL: 'url'
};
const DATETIME_FORMAT = { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' };

/**
 * A table drawn from a Reform blueprint: its columns, the records its filters allow, a page at a
 * time. Offers New, Edit and Delete only where the blueprint and the user's permissions allow them.
 *
 * Each row can be opened on its record page, so a list on a record page leads down to the next one.
 * Fires `new` when the user asks for a new record and `edit` with { recordId } for an existing one.
 * Deleting is done here, after the user confirms.
 */
export default class ReformList extends NavigationMixin(LightningElement) {
    /** The blueprint: a definition, { name } of a stored one, or both. */
    @api blueprint;
    /** Records per page. */
    @api pageSize = 10;

    view;
    busy = false;
    failure;
    skip = 0;

    connectedCallback() {
        this.load();
    }

    /** Loads the current page again. */
    @api
    refresh() {
        return this.load();
    }

    async load() {
        this.busy = true;
        try {
            // A page size set in markup arrives as text.
            const pageSize = Number(this.pageSize) || undefined;
            this.view = await listPage({ blueprint: this.blueprint, pageSize, skip: this.skip });
            this.failure = undefined;
        } catch (error) {
            this.failure = messageOf(error);
        } finally {
            this.busy = false;
        }
    }

    // Columns the blueprint got right. Each takes a safe key, since a path such as Account.Name
    // has a dot in it.
    get usableColumns() {
        if (!this.view) {
            return [];
        }
        return this.view.columns
            .filter((column) => !(column.problems || []).length)
            .map((column, index) => ({ ...column, key: `c${index}` }));
    }

    get columns() {
        const drawn = this.usableColumns.map((column) => {
            const type = COLUMN_TYPES[column.dataType] || 'text';
            const definition = { label: column.label, fieldName: column.key, type };
            if (column.dataType === 'DATETIME') {
                definition.typeAttributes = DATETIME_FORMAT;
            }
            return definition;
        });
        const actions = [{ label: 'Open', name: 'open' }];
        if (this.view && this.view.canEdit) {
            actions.push({ label: 'Edit', name: 'edit' });
        }
        if (this.view && this.view.canDelete) {
            actions.push({ label: 'Delete', name: 'delete' });
        }
        drawn.push({ type: 'action', typeAttributes: { rowActions: actions } });
        return drawn;
    }

    get rows() {
        if (!this.view) {
            return [];
        }
        const columns = this.usableColumns;
        return this.view.rows.map((row) => {
            const drawn = { Id: row.Id };
            columns.forEach((column) => {
                const value = row[column.name];
                // The platform stores 25 for 25%; the table's percent type wants 0.25.
                drawn[column.key] = column.dataType === 'PERCENT' && typeof value === 'number' ? value / 100 : value;
            });
            return drawn;
        });
    }

    get problems() {
        if (!this.view) {
            return [];
        }
        const found = [...(this.view.problems || [])];
        this.view.columns.forEach((column, index) => {
            (column.problems || []).forEach((problem) => found.push(`Column ${index + 1}: ${problem}`));
        });
        return found;
    }

    get hasProblems() {
        return this.problems.length > 0;
    }

    get heading() {
        return this.view ? `${this.view.pluralLabel} (${this.view.total})` : '';
    }

    get isEmpty() {
        return !!this.view && this.view.total === 0;
    }

    get hasRows() {
        return !!this.view && this.view.rows.length > 0;
    }

    get canCreate() {
        return !!this.view && this.view.canCreate;
    }

    get range() {
        if (!this.hasRows) {
            return '';
        }
        return `${this.view.skip + 1}–${this.view.skip + this.view.rows.length} of ${this.view.total}`;
    }

    get onFirstPage() {
        return this.skip === 0;
    }

    get onLastPage() {
        return !this.view || this.view.skip + this.view.rows.length >= this.view.total;
    }

    get showPaging() {
        return !!this.view && this.view.total > this.view.pageSize;
    }

    handleNew() {
        this.dispatchEvent(new CustomEvent('new'));
    }

    handlePrevious() {
        this.skip = Math.max(0, this.skip - this.view.pageSize);
        this.load();
    }

    handleNext() {
        this.skip += this.view.pageSize;
        this.load();
    }

    async handleRowAction(event) {
        const { action, row } = event.detail;
        if (action.name === 'open') {
            this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: row.Id, actionName: 'view' } });
        } else if (action.name === 'edit') {
            this.dispatchEvent(new CustomEvent('edit', { detail: { recordId: row.Id } }));
        } else if (action.name === 'delete') {
            await this.remove(row.Id);
        }
    }

    async remove(recordId) {
        const confirmed = await LightningConfirm.open({
            label: `Delete ${this.view.label}`,
            message: 'It will go to the Recycle Bin.',
            theme: 'warning'
        });
        if (!confirmed) {
            return;
        }
        this.busy = true;
        try {
            await removeRecord({ blueprint: this.blueprint, recordId });
            this.dispatchEvent(new ShowToastEvent({ title: `${this.view.label} deleted`, variant: 'success' }));
            // Deleting the last row of a page leaves nothing to show there.
            if (this.view.rows.length === 1 && this.skip > 0) {
                this.skip = Math.max(0, this.skip - this.view.pageSize);
            }
            await this.load();
        } catch (error) {
            this.failure = messageOf(error);
            this.busy = false;
        }
    }
}

function messageOf(error) {
    if (error && error.body && error.body.message) {
        return error.body.message;
    }
    return (error && error.message) || 'Something went wrong';
}
