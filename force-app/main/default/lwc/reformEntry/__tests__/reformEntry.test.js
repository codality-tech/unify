import { createElement } from 'lwc';
import ReformEntry from 'c/reformEntry';
import computeForm from '@salesforce/apex/ReformApi.form';

jest.mock('@salesforce/apex/ReformApi.form', () => ({ default: jest.fn() }), { virtual: true });

const BLUEPRINT = { sobjectName: 'Opportunity' };
const DEAL_ID = '006000000000001AAA';

function part(overrides) {
    return { kind: 'FIELD', width: 12, visible: true, problems: [], required: false, readOnly: false, reactive: false, ...overrides };
}

function view(overrides = {}) {
    return {
        objectName: 'Opportunity',
        label: 'Deal',
        recordId: null,
        saved: false,
        problems: [],
        parts: [
            part({ name: 'Name', label: 'Name', dataType: 'STRING', value: null, required: true }),
            part({ name: 'Amount', label: 'Amount', dataType: 'CURRENCY', value: null, reactive: true, width: 6 }),
            part({ name: 'NextStep', label: 'Next Step', dataType: 'STRING', value: 'Call', visible: false }),
            part({
                name: 'StageName',
                label: 'Stage',
                dataType: 'PICKLIST',
                value: 'Prospecting',
                options: [{ label: 'Prospecting', value: 'Prospecting' }]
            }),
            part({ name: 'AccountId', label: 'Account', dataType: 'REFERENCE', lookupTo: 'Account', value: null, reactive: true }),
            part({ name: 'IsPrivate', label: 'Private', dataType: 'BOOLEAN', value: true }),
            part({ name: 'Description', label: 'Description', dataType: 'TEXTAREA', value: 'Notes' }),
            part({ kind: 'HEADING', content: 'About the deal' }),
            part({ kind: 'RICH_TEXT', content: '<b>Acme</b>' }),
            part({ kind: 'SPACER' })
        ],
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
    const element = createElement('c-reform-entry', { is: ReformEntry });
    Object.assign(element, { blueprint: BLUEPRINT }, properties);
    document.body.appendChild(element);
    await flush();
    return element;
}

function inputFor(element, field) {
    return element.shadowRoot.querySelector(`[data-field="${field}"]`);
}

function change(input, detail) {
    input.dispatchEvent(new CustomEvent('change', { detail }));
}

describe('c-reform-entry', () => {
    beforeEach(() => {
        computeForm.mockResolvedValue(view());
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('asks the server for the form and draws each visible part with a control for its type', async () => {
        const element = await mount();
        const root = element.shadowRoot;

        expect(computeForm).toHaveBeenCalledWith({ blueprint: BLUEPRINT, values: {}, save: false });
        expect(root.querySelector('[data-id="title"]').textContent).toBe('New Deal');

        const name = inputFor(element, 'Name');
        expect(name.tagName).toBe('LIGHTNING-INPUT');
        expect(name.type).toBe('text');
        expect(name.required).toBe(true);

        const amount = inputFor(element, 'Amount');
        expect(amount.type).toBe('number');
        expect(amount.formatter).toBe('currency');
        expect(amount.parentElement.className).toContain('slds-medium-size_6-of-12');

        expect(inputFor(element, 'NextStep')).toBeNull();

        const stage = inputFor(element, 'StageName');
        expect(stage.tagName).toBe('LIGHTNING-COMBOBOX');
        expect(stage.value).toBe('Prospecting');
        expect(stage.options).toEqual([{ label: 'Prospecting', value: 'Prospecting' }]);

        const account = inputFor(element, 'AccountId');
        expect(account.tagName).toBe('LIGHTNING-RECORD-PICKER');
        expect(account.objectApiName).toBe('Account');

        const isPrivate = inputFor(element, 'IsPrivate');
        expect(isPrivate.type).toBe('checkbox');
        expect(isPrivate.checked).toBe(true);

        expect(inputFor(element, 'Description').tagName).toBe('LIGHTNING-TEXTAREA');
        expect(root.querySelector('[data-id="heading"]').textContent).toBe('About the deal');
        expect(root.querySelector('[data-id="rich-text"]').value).toBe('<b>Acme</b>');
        expect(root.querySelector('[data-id="save"]')).not.toBeNull();
    });

    it('asks again, after a pause, when a field the blueprint depends on changes', async () => {
        jest.useFakeTimers();
        const element = await mount();

        change(inputFor(element, 'Amount'), { value: '2500' });
        expect(computeForm).toHaveBeenCalledTimes(1);

        jest.advanceTimersByTime(400);
        await flush();

        expect(computeForm).toHaveBeenCalledTimes(2);
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, values: { Amount: 2500 }, save: false });
    });

    it('keeps other changes to itself until they are needed', async () => {
        jest.useFakeTimers();
        const element = await mount();

        change(inputFor(element, 'Name'), { value: 'Big deal' });
        jest.advanceTimersByTime(1000);
        await flush();
        expect(computeForm).toHaveBeenCalledTimes(1);

        change(inputFor(element, 'AccountId'), { recordId: '001000000000001AAA' });
        jest.advanceTimersByTime(400);
        await flush();
        expect(computeForm).toHaveBeenLastCalledWith({
            blueprint: BLUEPRINT,
            values: { Name: 'Big deal', AccountId: '001000000000001AAA' },
            save: false
        });
    });

    it('sends each kind of value as the server expects it', async () => {
        jest.useFakeTimers();
        const element = await mount();
        const isPrivate = inputFor(element, 'IsPrivate');

        change(inputFor(element, 'Name'), { value: '' });
        isPrivate.checked = false;
        change(isPrivate, {});
        change(inputFor(element, 'AccountId'), { recordId: null });
        change(inputFor(element, 'Amount'), { value: '12.5' });
        jest.advanceTimersByTime(400);
        await flush();

        expect(computeForm).toHaveBeenLastCalledWith({
            blueprint: BLUEPRINT,
            values: { Name: null, IsPrivate: false, AccountId: null, Amount: 12.5 },
            save: false
        });
    });

    it('saves what changed, shows the saved record and tells its host', async () => {
        computeForm.mockResolvedValue(view({ recordId: DEAL_ID }));
        const element = await mount({ recordId: DEAL_ID });
        const saved = jest.fn();
        const toast = jest.fn();
        element.addEventListener('saved', saved);
        element.addEventListener('lightning__showtoast', toast);
        expect(element.shadowRoot.querySelector('[data-id="title"]').textContent).toBe('Edit Deal');
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, values: { Id: DEAL_ID }, save: false });

        change(inputFor(element, 'Name'), { value: 'Renamed' });
        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flush();

        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, values: { Name: 'Renamed', Id: DEAL_ID }, save: true });
        expect(saved).toHaveBeenCalledTimes(1);
        expect(saved.mock.calls[0][0].detail).toEqual({ recordId: DEAL_ID });
        expect(toast.mock.calls[0][0].detail.title).toBe('Deal saved');
    });

    it('can be saved by its host, which may hide the buttons', async () => {
        computeForm.mockResolvedValue(view({ recordId: DEAL_ID }));
        const element = await mount({ hideActions: true });
        expect(element.shadowRoot.querySelector('[data-id="save"]')).toBeNull();

        await expect(element.save()).resolves.toBe(DEAL_ID);
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, values: {}, save: true });
    });

    it('shows the message the server gives when something fails', async () => {
        const element = await mount();
        computeForm.mockRejectedValue({ body: { message: 'Required: Name' } });
        const saved = jest.fn();
        element.addEventListener('saved', saved);

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flush();

        expect(element.shadowRoot.querySelector('[data-id="failure"]').textContent).toBe('Required: Name');
        expect(saved).not.toHaveBeenCalled();
    });

    it('lists the mistakes in a blueprint, saying where they are', async () => {
        computeForm.mockResolvedValue(
            view({
                problems: ['Opportunity has no record type Nope'],
                parts: [part({ kind: 'FIELD', visible: false, problems: ['Opportunity has no field named Nope__c'] })]
            })
        );
        const element = await mount();

        const listed = [...element.shadowRoot.querySelectorAll('[data-id="problem"]')].map((item) => item.textContent);
        expect(listed).toEqual(['Opportunity has no record type Nope', 'Element 1: Opportunity has no field named Nope__c']);
    });

    it('loads again when it is given another record', async () => {
        const element = await mount();
        element.recordId = DEAL_ID;
        await flush();

        expect(computeForm).toHaveBeenCalledTimes(2);
        expect(computeForm).toHaveBeenLastCalledWith({ blueprint: BLUEPRINT, values: { Id: DEAL_ID }, save: false });
    });

    it('tells its host when the user backs out', async () => {
        const element = await mount();
        const cancelled = jest.fn();
        element.addEventListener('cancel', cancelled);

        element.shadowRoot.querySelector('[data-id="cancel"]').click();

        expect(cancelled).toHaveBeenCalledTimes(1);
    });
});
