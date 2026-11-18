import { splitRows, isBlank, partsOf, lineOf } from '../csvParts';

describe('csvParts', () => {
    it('ends a row at any line break that is not inside quotes', () => {
        const rows = splitRows('Name,Note\r\n"Acme, Inc","said ""hi""\nthere"\rLast,row');

        expect(rows).toEqual(['Name,Note', '"Acme, Inc","said ""hi""\nthere"', 'Last,row']);
    });

    it('drops a byte order mark and keeps blank rows', () => {
        const rows = splitRows(String.fromCharCode(0xfeff) + 'a\n\nb\n');

        expect(rows).toEqual(['a', '', 'b']);
        expect(splitRows('')).toEqual([]);
        expect(splitRows(undefined)).toEqual([]);
    });

    it('knows a row with nothing in it', () => {
        expect(isBlank('')).toBe(true);
        expect(isBlank(' , ;"" |\t')).toBe(true);
        expect(isBlank(',x,')).toBe(false);
    });

    it('cuts a file into a header and parts that know where they sit', () => {
        const cut = partsOf('\nName\nOne\nTwo\n\nThree\nFour\n', 2);

        expect(cut.header).toBe('Name');
        expect(cut.count).toBe(4);
        expect(cut.parts).toEqual([
            { rowsBefore: 1, rows: ['One', 'Two'], count: 2 },
            { rowsBefore: 3, rows: ['', 'Three'], count: 1 },
            { rowsBefore: 5, rows: ['Four'], count: 1 }
        ]);
    });

    it('leaves out a part that holds only blank rows, and a file with nothing in it has no header', () => {
        expect(partsOf('Name\nOne\n\n\n', 1).parts).toEqual([{ rowsBefore: 0, rows: ['One'], count: 1 }]);
        expect(partsOf('\n , \n', 5)).toEqual({ header: null, count: 0, parts: [] });
        expect(partsOf('Name\n', 5)).toEqual({ header: 'Name', count: 0, parts: [] });
    });

    it('writes a line with every cell in quotes', () => {
        expect(lineOf(['Name', 'Said "hi"', 3])).toBe('"Name","Said ""hi""","3"');
    });
});
