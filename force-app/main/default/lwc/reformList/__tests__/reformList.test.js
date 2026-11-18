import { createElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import ReformList from 'c/reformList';
import listPage from '@salesforce/apex/ReformApi.table';
import removeRecord from '@salesforce/apex/ReformApi.remove';

jest.mock('@salesforce/apex/ReformApi.table', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ReformApi.remove', () => ({ default: jest.fn() }), { virtual: true });

const BLUEPRINT = { name: 'deals' };

function view(overrides = {}) {
    return {
        objectName: 'Opportunity',
        label: 'Deal',
        pluralLabel: 'Deals',
        problems: [],
        columns: [
            { name: 'Name', label: 'Name', dataType: 'STRING', problems: [] },
            { name: 'Account.Name', label: 'Account', dataType: 'STRING', problems: [] },
            { name: 'Probability', label: 'Probability', dataType: 'PERCENT', problems: [] },
            { name: 'CreatedDate', label: 'Created', dataType: 'DATETIME', problems: [] },
            { name: 'Nope', label: null, dataType: null, problems: ['Nope is not a field path on Opportunity'] }
        ],
        rows: [
            { Id: '006A', Name: 'First', 'Account.Name': 'Acme', Probability: 25, CreatedDate: '2030-01-15T10:00:00.000Z' },
            { Id: '006B', Name: 'Second', 'Account.Name': null, Probability: null, CreatedDate: '2030-01-16T10:00:00.000Z' }
        ],
        total: 12,
        pageSize: 2,
        skip: 0,
        canCreate: true,
        canEdit: true,
        canDelete: true,
        ...overrides
    };
}

async function flush() {
    for (let turn = 0; turn < 6; turn++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

async function mount(properties = {}) {
    const element = createElement('c-reform-list', { is: ReformList });
    Object.assign(element, { blueprint: BLUEPRINT, pageSize: 2 }, properties);
    document.body.appendChild(element);
    await flush();
    return element;
}

function rowAction(element, name, row) {
    element.shadowRoot.querySelector('lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name }, row } }));
}

describe('c-reform-list', () => {
    beforeEach(() => {
        listPage.mockResolvedValue(view());
        removeRecord.mockResolvedValue(undefined);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('draws the columns the blueprint got right and reports the ones it did not', async () => {
        const element = await mount();
        const root = element.shadowRoot;
        const table = root.querySelector('lightning-datatable');

        expect(listPage).toHaveBeenCalledWith({ blueprint: BLUEPRINT, pageSize: 2, skip: 0 });
        expect(root.querySelector('[data-id="heading"]').textContent).toBe('Deals (12)');
        expect(table.columns.map((column) => [column.label, column.fieldName, column.type])).toEqual([
            ['Name', 'c0', 'text'],
            ['Account', 'c1', 'text'],
            ['Probability', 'c2', 'percent'],
            ['Created', 'c3', 'date'],
            [undefined, undefined, 'action']
        ]);
        expect(table.columns[4].typeAttributes.rowActions.map((action) => action.name)).toEqual(['edit', 'delete']);
        expect(table.data).toEqual([
            { Id: '006A', c0: 'First', c1: 'Acme', c2: 0.25, c3: '2030-01-15T10:00:00.000Z' },
            { Id: '006B', c0: 'Second', c1: null, c2: null, c3: '2030-01-16T10:00:00.000Z' }
        ]);
        expect([...root.querySelectorAll('[data-id="problem"]')].map((item) => item.textContent)).toEqual([
            'Column 5: Nope is not a field path on Opportunity'
        ]);
    });

    it('pages through the records', async () => {
        const element = await mount();
        const root = element.shadowRoot;

        expect(root.querySelector('[data-id="range"]').textContent).toBe('1–2 of 12');
        expect(root.querySelector('[data-id="previous"]').disabled).toBe(true);
        expect(root.querySelector('[data-id="next"]').disabled).toBe(false);

        listPage.mockResolvedValue(view({ skip: 2 }));
        root.querySelector('[data-id="next"]').click();
        await flush();

        expect(listPage).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, pageSize: 2, skip: 2 });
        expect(root.querySelector('[data-id="range"]').textContent).toBe('3–4 of 12');
        expect(root.querySelector('[data-id="previous"]').disabled).toBe(false);

        root.querySelector('[data-id="previous"]').click();
        await flush();
        expect(listPage).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, pageSize: 2, skip: 0 });
    });

    it('offers only what the blueprint and the user are allowed', async () => {
        listPage.mockResolvedValue(view({ canCreate: false, canEdit: false, canDelete: false, total: 2 }));
        const element = await mount();
        const root = element.shadowRoot;

        expect(root.querySelector('[data-id="new"]')).toBeNull();
        expect(root.querySelector('lightning-datatable').columns.some((column) => column.type === 'action')).toBe(false);
        expect(root.querySelector('[data-id="range"]')).toBeNull();
    });

    it('asks its host for a new record or an edit', async () => {
        const element = await mount();
        const asked = jest.fn();
        element.addEventListener('new', asked);
        element.addEventListener('edit', asked);

        element.shadowRoot.querySelector('[data-id="new"]').click();
        rowAction(element, 'edit', { Id: '006B' });

        expect(asked.mock.calls.map(([event]) => [event.type, event.detail])).toEqual([
            ['new', null],
            ['edit', { recordId: '006B' }]
        ]);
    });

    it('deletes after the user confirms, then loads again', async () => {
        LightningConfirm.open = jest.fn().mockResolvedValue(true);
        const element = await mount();

        rowAction(element, 'delete', { Id: '006A' });
        await flush();

        expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
        expect(removeRecord).toHaveBeenCalledWith({ blueprint: BLUEPRINT, recordId: '006A' });
        expect(listPage).toHaveBeenCalledTimes(2);
    });

    it('leaves the record alone when the user does not confirm', async () => {
        LightningConfirm.open = jest.fn().mockResolvedValue(false);
        const element = await mount();

        rowAction(element, 'delete', { Id: '006A' });
        await flush();

        expect(removeRecord).not.toHaveBeenCalled();
        expect(listPage).toHaveBeenCalledTimes(1);
    });

    it('says so when there is nothing to list', async () => {
        listPage.mockResolvedValue(view({ rows: [], total: 0 }));
        const element = await mount();
        const root = element.shadowRoot;

        expect(root.querySelector('lightning-datatable')).toBeNull();
        expect(root.querySelector('[data-id="empty"]')).not.toBeNull();
        expect(root.querySelector('[data-id="heading"]').textContent).toBe('Deals (0)');
    });

    it('shows the message the server gives when something fails', async () => {
        listPage.mockRejectedValue({ body: { message: 'There is no object named Nope__c' } });
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="failure"]').textContent).toBe('There is no object named Nope__c');
    });

    it('loads the current page again when asked', async () => {
        const element = await mount();
        await element.refresh();

        expect(listPage).toHaveBeenCalledTimes(2);
    });
});
