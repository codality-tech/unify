import { createElement } from 'lwc';
import ReformShowcase from 'c/reformShowcase';
import listPage from '@salesforce/apex/ReformApi.table';

jest.mock('@salesforce/apex/ReformApi.table', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ReformApi.form', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ReformApi.remove', () => ({ default: jest.fn() }), { virtual: true });

async function flush() {
    for (let turn = 0; turn < 8; turn++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

describe('c-reform-showcase', () => {
    beforeEach(() => {
        listPage.mockResolvedValue({ label: 'Record', pluralLabel: 'Records', problems: [], columns: [], rows: [], total: 0, pageSize: 5, skip: 0 });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows one sample at a time and builds a new panel for the one chosen', async () => {
        const element = createElement('c-reform-showcase', { is: ReformShowcase });
        document.body.appendChild(element);
        await flush();
        const chooser = element.shadowRoot.querySelector('lightning-radio-group');
        const firstPanel = element.shadowRoot.querySelector('c-reform-panel');

        expect(chooser.options.map((option) => option.value)).toEqual(['accounts', 'contacts', 'deals']);
        expect(firstPanel.blueprint.sobjectName).toBe('Account');
        expect(listPage.mock.calls[0][0]).toMatchObject({ pageSize: 5, skip: 0 });

        chooser.dispatchEvent(new CustomEvent('change', { detail: { value: 'deals' } }));
        await flush();

        const panels = element.shadowRoot.querySelectorAll('c-reform-panel');
        expect(panels).toHaveLength(1);
        expect(panels[0]).not.toBe(firstPanel);
        expect(panels[0].blueprint.sobjectName).toBe('Opportunity');
        expect(listPage.mock.calls[1][0].blueprint.filters).toEqual(['IsClosed = false']);
    });
});
