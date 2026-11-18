import { LightningElement } from 'lwc';

// Blueprints written here rather than stored, so the showcase works in an org with no setup.
const SAMPLES = [
    {
        label: 'Accounts',
        value: 'accounts',
        note: 'A plain form and table. The note about revenue appears once the figure passes a million.',
        blueprint: {
            sobjectName: 'Account',
            elements: [
                { width: 8, field: { name: 'Name' } },
                { width: 4, field: { name: 'Type' } },
                { width: 6, field: { name: 'Industry' } },
                { width: 6, field: { name: 'AnnualRevenue' } },
                { visible: 'AnnualRevenue > 1000000', richtext: { content: '<b>{!Name}</b> is a large account.' } },
                { width: 6, field: { name: 'Phone' } },
                { width: 6, field: { name: 'Website' } }
            ],
            columns: [{ name: 'Name' }, { name: 'Type' }, { name: 'Industry' }, { name: 'Owner.Name', label: 'Owner' }]
        }
    },
    {
        label: 'Contacts',
        value: 'contacts',
        note: 'Pick an account and the line under it reads through the lookup, before anything is saved.',
        blueprint: {
            sobjectName: 'Contact',
            elements: [
                { field: { name: 'AccountId' } },
                {
                    visible: 'AccountId != null',
                    richtext: { content: 'Works at <b>{!Account.Name}</b>, an account owned by {!Account.Owner.Name}.' }
                },
                { width: 6, field: { name: 'FirstName' } },
                { width: 6, field: { name: 'LastName' } },
                { width: 6, field: { name: 'Title' } },
                { width: 6, field: { name: 'Email' } }
            ],
            columns: [{ name: 'Name' }, { name: 'Account.Name', label: 'Account' }, { name: 'Title' }, { name: 'Email' }]
        }
    },
    {
        label: 'Open deals',
        value: 'deals',
        note: 'The table lists open deals only. Next step is asked for once the amount passes 100,000.',
        blueprint: {
            sobjectName: 'Opportunity',
            label: 'Deal',
            pluralLabel: 'Open deals',
            elements: [
                { width: 6, field: { name: 'Name' } },
                { width: 6, field: { name: 'AccountId' } },
                { heading: { content: 'Stage and size' } },
                { width: 4, field: { name: 'StageName', defaultValue: 'Prospecting' } },
                { width: 4, field: { name: 'CloseDate' } },
                { width: 4, field: { name: 'Amount' } },
                { visible: 'Amount > 100000', field: { name: 'NextStep', required: true, defaultValue: 'Brief the account team' } }
            ],
            columns: [
                { name: 'Name' },
                { name: 'Account.Name', label: 'Account' },
                { name: 'StageName' },
                { name: 'Amount' },
                { name: 'CloseDate' }
            ],
            filters: ['IsClosed = false']
        }
    }
];

/** A few blueprints to try Reform with. */
export default class ReformShowcase extends LightningElement {
    chosen = SAMPLES[0].value;

    get options() {
        return SAMPLES.map(({ label, value }) => ({ label, value }));
    }

    // A list of one, keyed by the sample, so choosing another sample builds a new panel.
    get shown() {
        return SAMPLES.filter((sample) => sample.value === this.chosen);
    }

    handleChoose(event) {
        this.chosen = event.detail.value;
    }
}
