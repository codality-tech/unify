import { createElement } from 'lwc';
import ImportPanel from 'c/importPanel';
import listFormats from '@salesforce/apex/ImportApi.formats';
import runFormat from '@salesforce/apex/ImportApi.run';

jest.mock('@salesforce/apex/ImportApi.formats', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ImportApi.run', () => ({ default: jest.fn() }), { virtual: true });

const PEOPLE = {
    name: 'People',
    label: 'People from events',
    summary: 'Creates or updates Contacts, matched on Email',
    headers: ['Email', 'Surname'],
    allOrNothing: false
};
const FIRMS = { name: 'Firms', label: 'Firms, by header', summary: 'Creates Accounts. Saves every row or none', headers: [], allOrNothing: true };

function result(given = {}) {
    return { rows: 0, created: 0, updated: 0, failed: 0, held: 0, columns: [], ignored: [], notes: [], failures: [], failuresCsv: null, ...given };
}

// The file reader answers on a later task, not a microtask.
async function flush() {
    for (let turn = 0; turn < 4; turn++) {
        // eslint-disable-next-line no-await-in-loop, @lwc/lwc/no-async-operation
        await new Promise((resolve) => setTimeout(resolve, 0));
    }
}

async function mount(properties = {}) {
    const element = createElement('c-import-panel', { is: ImportPanel });
    Object.assign(element, properties);
    document.body.appendChild(element);
    await flush();
    return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const textOf = (element, id) => find(element, id).textContent.replace(/\s+/g, ' ').trim();

async function pick(element, text, name = 'people.csv') {
    const input = find(element, 'file');
    Object.defineProperty(input, 'files', { value: text === null ? [] : [new File([text], name, { type: 'text/csv' })], configurable: true });
    input.dispatchEvent(new CustomEvent('change'));
    await flush();
}

async function press(element, id) {
    find(element, id).click();
    await flush();
}

function rowsOf(count) {
    let text = 'Email,Surname\n';
    for (let at = 1; at <= count; at++) {
        text += `p${at}@example.com,Person ${at}\n`;
    }
    return text;
}

describe('c-import-panel', () => {
    beforeEach(() => {
        listFormats.mockResolvedValue([FIRMS, PEOPLE]);
        runFormat.mockResolvedValue(result());
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('offers the formats and waits for one to be chosen', async () => {
        const element = await mount();

        expect(find(element, 'title').textContent).toBe('Import');
        expect(find(element, 'format').options).toEqual([
            { label: 'Firms, by header', value: 'Firms' },
            { label: 'People from events', value: 'People' }
        ]);
        expect(find(element, 'summary')).toBeNull();
        expect(find(element, 'file')).toBeNull();
    });

    it('describes the chosen format and offers an empty file with its headers', async () => {
        const element = await mount();

        find(element, 'format').dispatchEvent(new CustomEvent('change', { detail: { value: 'People' } }));
        await flush();

        expect(textOf(element, 'summary')).toBe('Creates or updates Contacts, matched on Email.');
        expect(textOf(element, 'headers')).toContain('Columns: Email, Surname.');
        expect(find(element, 'template').getAttribute('href')).toBe('data:text/csv;charset=utf-8,' + encodeURIComponent('"Email","Surname"\n'));
        expect(find(element, 'template').getAttribute('download')).toBe('People.csv');
        expect(find(element, 'check').disabled).toBe(true);
    });

    it('says a format with no columns reads the file by its headers', async () => {
        listFormats.mockResolvedValue([FIRMS]);
        const element = await mount();

        expect(find(element, 'format')).toBeNull();
        expect(textOf(element, 'summary')).toBe('Creates Accounts. Saves every row or none.');
        expect(textOf(element, 'headers')).toBe("Each column is read by its header: a field's name or label.");
        expect(find(element, 'template')).toBeNull();
    });

    it('offers one format only when it is given one', async () => {
        const element = await mount({ format: 'People', title: 'Import people' });

        expect(find(element, 'title').textContent).toBe('Import people');
        expect(find(element, 'format')).toBeNull();
        expect(textOf(element, 'summary')).toBe('Creates or updates Contacts, matched on Email.');
    });

    it('says so when the format it was given cannot run, or there are none', async () => {
        const wrong = await mount({ format: 'Gone' });
        listFormats.mockResolvedValue([]);
        const empty = await mount();
        listFormats.mockRejectedValue({ body: { message: 'No access' } });
        const refused = await mount();

        expect(textOf(wrong, 'problem')).toBe('There is no import format named Gone that can run.');
        expect(find(wrong, 'file')).toBeNull();
        expect(find(empty, 'none')).not.toBeNull();
        expect(textOf(refused, 'problem')).toBe('No access');
    });

    it('counts the rows of a file and refuses an empty one', async () => {
        const element = await mount({ format: 'People' });

        await pick(element, 'Email,Surname\na@example.com,A\n\nb@example.com,"B\nC"\n');
        expect(textOf(element, 'file-note')).toBe('people.csv: 2 rows');
        expect(find(element, 'import').disabled).toBe(false);

        await pick(element, '\n,\n');
        expect(textOf(element, 'problem')).toBe('That file is empty.');
        expect(find(element, 'file-note')).toBeNull();
        expect(find(element, 'import').disabled).toBe(true);

        await pick(element, null);
        expect(find(element, 'problem')).toBeNull();
    });

    it('checks a file without saving it', async () => {
        runFormat.mockResolvedValue(
            result({
                rows: 2,
                created: 1,
                failed: 1,
                columns: ['Email fills Email', 'Surname fills Last Name'],
                ignored: ['Notes'],
                failures: [{ row: 3, message: 'Surname is empty' }],
                failuresCsv: '"Email","Surname","Error"\n"b@example.com","","Surname is empty"'
            })
        );
        const element = await mount({ format: 'People' });
        const checked = jest.fn();
        element.addEventListener('checked', checked);
        await pick(element, 'Email,Surname\na@example.com,A\nb@example.com,\n');

        await press(element, 'check');

        expect(runFormat).toHaveBeenCalledWith({ format: 'People', text: 'Email,Surname\na@example.com,A\nb@example.com,', rowsBefore: 0, save: false });
        expect(textOf(element, 'headline')).toBe('An import would create 1 and update 0. 1 of 2 rows have something wrong.');
        const notes = [...element.shadowRoot.querySelectorAll('[data-id="note"]')].map((note) => note.textContent);
        expect(notes).toEqual(['Columns not read: Notes', 'A check cannot see what validation rules, triggers and duplicate rules will say.']);
        expect([...element.shadowRoot.querySelectorAll('[data-id="reading"]')].map((each) => each.textContent)).toEqual([
            'Email fills Email',
            'Surname fills Last Name'
        ]);
        expect(find(element, 'failures').data).toEqual([{ row: 3, message: 'Surname is empty' }]);
        expect(find(element, 'failures-file').getAttribute('download')).toBe('people-failed.csv');
        expect(checked).toHaveBeenCalledTimes(1);
        expect(checked.mock.calls[0][0].detail.failed).toBe(1);
    });

    it('imports a long file in parts and adds up what each part did', async () => {
        runFormat
            .mockResolvedValueOnce(
                result({
                    rows: 200,
                    created: 199,
                    failed: 1,
                    notes: ['A note'],
                    failures: [{ row: 7, message: 'bad' }],
                    failuresCsv: '"Email","Surname","Error"\n"p6@example.com","","bad"'
                })
            )
            .mockResolvedValueOnce(result({ rows: 200, created: 100, updated: 100, notes: ['A note'] }))
            .mockResolvedValueOnce(
                result({
                    rows: 50,
                    updated: 49,
                    failed: 1,
                    failures: [{ row: 450, message: 'worse' }],
                    failuresCsv: '"Email","Surname","Error"\n"p449@example.com","","worse"'
                })
            );
        const element = await mount({ format: 'People' });
        const imported = jest.fn();
        element.addEventListener('imported', imported);
        await pick(element, rowsOf(450));

        await press(element, 'import');

        expect(runFormat).toHaveBeenCalledTimes(3);
        expect(runFormat.mock.calls.map(([sent]) => [sent.rowsBefore, sent.save, sent.text.split('\n').length])).toEqual([
            [0, true, 201],
            [200, true, 201],
            [400, true, 51]
        ]);
        expect(runFormat.mock.calls[2][0].text.startsWith('Email,Surname\np401@example.com,Person 401\n')).toBe(true);
        expect(textOf(element, 'headline')).toBe('Created 299, updated 149. 2 of 450 rows failed.');
        expect([...element.shadowRoot.querySelectorAll('[data-id="note"]')].map((note) => note.textContent)).toEqual(['A note']);
        expect(find(element, 'failures').data.map((failure) => failure.row)).toEqual([7, 450]);
        expect(decodeURIComponent(find(element, 'failures-file').getAttribute('href'))).toBe(
            'data:text/csv;charset=utf-8,"Email","Surname","Error"\n"p6@example.com","","bad"\n"p449@example.com","","worse"'
        );
        expect(find(element, 'progress')).toBeNull();
        expect(imported.mock.calls[0][0].detail).toMatchObject({ save: true, rows: 450, created: 299, updated: 149, failed: 2 });
    });

    it('sends a file whole when the format saves every row or none', async () => {
        runFormat.mockResolvedValue(result({ rows: 450, failed: 1, held: 449, failures: [{ row: 9, message: 'bad' }] }));
        listFormats.mockResolvedValue([FIRMS]);
        const element = await mount();
        await pick(element, rowsOf(450));

        await press(element, 'import');

        expect(runFormat).toHaveBeenCalledTimes(1);
        expect(runFormat.mock.calls[0][0].text.split('\n').length).toBe(451);
        expect(textOf(element, 'headline')).toBe('Nothing was saved: 1 of 450 rows failed, and this format saves every row or none.');
        expect(find(element, 'failures-file')).toBeNull();
    });

    it('stops at a part the server refuses and says how far it got', async () => {
        runFormat.mockResolvedValueOnce(result({ rows: 200, created: 200 })).mockRejectedValueOnce({ body: { message: 'You cannot create Contacts' } });
        const element = await mount({ format: 'People' });
        await pick(element, rowsOf(450));

        await press(element, 'import');

        expect(runFormat).toHaveBeenCalledTimes(2);
        expect(textOf(element, 'problem')).toBe('You cannot create Contacts It stopped after row 200 of 450; what came before stands.');
        expect(textOf(element, 'headline')).toBe('Created 200, updated 0. 0 of 200 rows failed.');
    });

    it('shows only the refusal when the first part is refused', async () => {
        runFormat.mockRejectedValue({ body: { message: 'The file does not fit the format People: it has no column headed Surname' } });
        const element = await mount({ format: 'People' });
        await pick(element, 'Email\na@example.com\n');

        await press(element, 'import');

        expect(textOf(element, 'problem')).toBe('The file does not fit the format People: it has no column headed Surname');
        expect(find(element, 'outcome')).toBeNull();
    });

    it('says so when the file has a header and nothing under it', async () => {
        const element = await mount({ format: 'People' });
        await pick(element, 'Email,Surname\n');

        await press(element, 'check');

        expect(runFormat).not.toHaveBeenCalled();
        expect(textOf(element, 'headline')).toBe('The file has no rows under its header.');
    });

    it('lists the first hundred failures and says how many more the file holds', async () => {
        const failures = [];
        for (let row = 2; row <= 131; row++) {
            failures.push({ row, message: 'bad' });
        }
        runFormat.mockResolvedValue(result({ rows: 130, failed: 130, failures, failuresCsv: '"Email","Error"\n"x","bad"' }));
        const element = await mount({ format: 'People' });
        await pick(element, rowsOf(130));

        await press(element, 'import');

        expect(find(element, 'failures').data.length).toBe(100);
        expect(textOf(element, 'more')).toBe('and 30 more, all of them in the file below.');
    });
});
