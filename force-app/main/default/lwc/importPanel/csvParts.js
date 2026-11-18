// Cutting CSV text into rows without reading the cells. The server reads the cells; the component
// only needs to know where each row ends, so that a large file can be sent in parts.

const BYTE_ORDER_MARK = String.fromCharCode(0xfeff);

/** The rows of the text, each as it was written. A line break inside quotes does not end a row. */
export function splitRows(text) {
    const given = text || '';
    const body = given.startsWith(BYTE_ORDER_MARK) ? given.slice(1) : given;
    const rows = [];
    let start = 0;
    let quoted = false;
    for (let at = 0; at < body.length; at++) {
        const character = body[at];
        if (character === '"') {
            quoted = !quoted;
        } else if (!quoted && (character === '\n' || character === '\r')) {
            rows.push(body.slice(start, at));
            if (character === '\r' && body[at + 1] === '\n') {
                at++;
            }
            start = at + 1;
        }
    }
    if (start < body.length) {
        rows.push(body.slice(start));
    }
    return rows;
}

/** Whether a row holds nothing but separators, quotes and white space. */
export function isBlank(row) {
    return row.replace(/[\s,;|"]/g, '') === '';
}

/**
 * The text as a header and parts of at most `size` rows. Each part says how many rows of the file
 * come before its own, blank ones included, so the server can name a row as the file has it.
 */
export function partsOf(text, size) {
    const rows = splitRows(text);
    const headerAt = rows.findIndex((row) => !isBlank(row));
    if (headerAt < 0) {
        return { header: null, count: 0, parts: [] };
    }
    const under = rows.slice(headerAt + 1);
    const parts = [];
    for (let from = 0; from < under.length; from += size) {
        const some = under.slice(from, from + size);
        if (some.some((row) => !isBlank(row))) {
            parts.push({ rowsBefore: headerAt + from, rows: some, count: some.filter((row) => !isBlank(row)).length });
        }
    }
    return { header: rows[headerAt], count: under.filter((row) => !isBlank(row)).length, parts };
}

/** One line of CSV for the cells given, each in quotes. */
export function lineOf(cells) {
    return cells.map((cell) => '"' + String(cell).replace(/"/g, '""') + '"').join(',');
}
