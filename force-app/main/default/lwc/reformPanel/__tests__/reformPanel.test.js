import { createElement } from 'lwc';
import ReformPanel from 'c/reformPanel';
import listPage from '@salesforce/apex/ReformApi.table';
import computeForm from '@salesforce/apex/ReformApi.form';

jest.mock('@salesforce/apex/ReformApi.table', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ReformApi.form', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ReformApi.remove', () => ({ default: jest.fn() }), { virtual: true });

const ACCOUNT_ID = '001000000000001AAA';

const TABLE = {
    label: 'Contact',
    pluralLabel: 'Contacts',
    problems: [],
    columns: [{ name: 'Name', label: 'Name', dataType: 'STRING', problems: [] }],
    rows: [{ Id: '003A', Name: 'Ada' }],
    total: 1,
    pageSize: 10,
    skip: 0,
    canCreate: true,
    canEdit: true,
    canDelete: true
};
const FORM = { label: 'Contact', recordId: null, problems: [], parts: [] };

async function flush() {
    for (let turn = 0; turn < 8; turn++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

async function mount(properties = {}) {
    const element = createElement('c-reform-panel', { is: ReformPanel });
    Object.assign(element, properties);
    document.body.appendChild(element);
    await flush();
    return element;
}

const listIn = (element) => element.shadowRoot.querySelector('c-reform-list');
const entryIn = (element) => element.shadowRoot.querySelector('c-reform-entry');

describe('c-reform-panel', () => {
    beforeEach(() => {
        listPage.mockResolvedValue(TABLE);
        computeForm.mockResolvedValue(FORM);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('asks for a blueprint when it has none', async () => {
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="unconfigured"]')).not.toBeNull();
        expect(listIn(element)).toBeNull();
        expect(listPage).not.toHaveBeenCalled();
    });

    it('lists a stored blueprint by its name', async () => {
        const element = await mount({ blueprintName: 'people', title: 'People', pageSize: 5 });

        expect(element.shadowRoot.querySelector('[data-id="title"]').textContent).toBe('People');
        expect(listPage).toHaveBeenCalledWith({ blueprint: { name: 'people' }, pageSize: 5, skip: 0 });
    });

    it('becomes a related list when given the field that points at the page record', async () => {
        await mount({ blueprintName: 'people', parentField: 'AccountId', recordId: ACCOUNT_ID });

        expect(listPage.mock.calls[0][0].blueprint).toEqual({
            name: 'people',
            parameters: [{ name: 'AccountId', fixedValue: ACCOUNT_ID }]
        });
    });

    it('lays a definition it is handed over the stored blueprint, keeping its parameters', async () => {
        const blueprint = { sobjectName: 'Contact', parameters: [{ name: 'Title', fixedValue: 'CTO' }] };
        await mount({ blueprint, blueprintName: 'people', parentField: 'AccountId', recordId: ACCOUNT_ID });

        expect(listPage.mock.calls[0][0].blueprint).toEqual({
            sobjectName: 'Contact',
            name: 'people',
            parameters: [
                { name: 'Title', fixedValue: 'CTO' },
                { name: 'AccountId', fixedValue: ACCOUNT_ID }
            ]
        });
        expect(blueprint.parameters).toHaveLength(1);
    });

    it('swaps the list for the form while a record is entered, and back when it is done', async () => {
        const element = await mount({ blueprintName: 'people' });

        listIn(element).dispatchEvent(new CustomEvent('new'));
        await flush();
        expect(listIn(element)).toBeNull();
        expect(entryIn(element).recordId).toBeUndefined();
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: { name: 'people' }, values: {}, save: false });

        entryIn(element).dispatchEvent(new CustomEvent('cancel'));
        await flush();
        expect(entryIn(element)).toBeNull();
        expect(listPage).toHaveBeenCalledTimes(2);

        listIn(element).dispatchEvent(new CustomEvent('edit', { detail: { recordId: '003A' } }));
        await flush();
        expect(entryIn(element).recordId).toBe('003A');
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: { name: 'people' }, values: { Id: '003A' }, save: false });

        entryIn(element).dispatchEvent(new CustomEvent('saved', { detail: { recordId: '003A' } }));
        await flush();
        expect(listIn(element)).not.toBeNull();
        expect(listPage).toHaveBeenCalledTimes(3);
    });

    it("enters a record for one of the form's lookups in a form of its own, and hands it back", async () => {
        const element = await mount({ blueprintName: 'people' });
        listIn(element).dispatchEvent(new CustomEvent('new'));
        await flush();
        const outer = element.shadowRoot.querySelector('[data-id="entry"]');

        outer.dispatchEvent(new CustomEvent('createrecord', { detail: { field: 'AccountId', blueprint: { name: 'new_company' }, label: 'New Account' } }));
        await flush();
        const made = element.shadowRoot.querySelector('[data-id="made-entry"]');
        expect(made.blueprint).toEqual({ name: 'new_company' });
        expect(made.hideActions).toBe(true);
        expect(outer.parentElement.className).toContain('slds-hide');
        expect(element.shadowRoot.querySelector('[data-id="made-use"]').label).toBe('Use this account');

        element.shadowRoot.querySelector('[data-id="made-use"]').click();
        await flush();
        expect(element.shadowRoot.querySelector('[data-id="made-entry"]')).toBeNull();
        expect(outer.parentElement.className).not.toContain('slds-hide');

        await outer.save();
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: { name: 'people' }, values: { AccountId: { create: {} } }, save: true });
    });

    it('goes back to the form without the record when the user backs out of it', async () => {
        const element = await mount({ blueprintName: 'people' });
        listIn(element).dispatchEvent(new CustomEvent('new'));
        await flush();
        const outer = element.shadowRoot.querySelector('[data-id="entry"]');
        outer.dispatchEvent(new CustomEvent('createrecord', { detail: { field: 'AccountId', blueprint: { name: 'new_company' }, label: 'New Account' } }));
        await flush();

        element.shadowRoot.querySelector('[data-id="made-back"]').click();
        await flush();

        expect(element.shadowRoot.querySelector('[data-id="made-entry"]')).toBeNull();
        await outer.save();
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: { name: 'people' }, values: {}, save: true });
    });
});
