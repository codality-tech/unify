import { LightningElement, api } from 'lwc';

/**
 * A blueprint's table and form together: the list, with New, Edit and Delete, and the form in its
 * place while a record is being entered.
 *
 * On a record page, set "parent field" to the lookup that points at the page's record. The panel
 * then lists only that record's children and files new ones under it: a related list drawn from a
 * blueprint.
 */
export default class ReformPanel extends LightningElement {
    /** API name of a stored blueprint. */
    @api blueprintName;
    /** A blueprint definition, for a parent component that builds one; laid over the stored one if both are given. */
    @api blueprint;
    /** A lookup on the blueprint's object to fix to this page's record. */
    @api parentField;
    /** Set by a record page. */
    @api recordId;
    @api pageSize = 10;
    @api title;

    entering = false;
    enteringId;

    built;
    builtFrom;

    // The blueprint the children are given. It is built once per set of inputs, so the children are
    // not handed a new object on every render.
    get definition() {
        const from = JSON.stringify([this.blueprintName, this.blueprint, this.parentField, this.recordId]);
        if (from !== this.builtFrom) {
            const definition = this.blueprint ? JSON.parse(JSON.stringify(this.blueprint)) : {};
            if (this.blueprintName && !definition.name) {
                definition.name = this.blueprintName;
            }
            if (this.parentField && this.recordId) {
                definition.parameters = [...(definition.parameters || []), { name: this.parentField, fixedValue: this.recordId }];
            }
            this.built = definition;
            this.builtFrom = from;
        }
        return this.built;
    }

    get configured() {
        return !!this.blueprintName || !!this.blueprint;
    }

    handleNew() {
        this.enteringId = undefined;
        this.entering = true;
    }

    handleEdit(event) {
        this.enteringId = event.detail.recordId;
        this.entering = true;
    }

    // Saved or cancelled: back to the list, which loads afresh.
    handleDone() {
        this.entering = false;
        this.enteringId = undefined;
    }
}
