import { LightningElement, api, wire, track } from 'lwc';
import getAccounts from '@salesforce/apex/AccountOpportunitiesController.getAccounts';
import getOpportunityTotal from '@salesforce/apex/AccountOpportunitiesController.getOpportunityTotal';

export default class AccountOpportunitiesSummary extends LightningElement {
    @api title = 'Account Opportunities Summary';
    @track selectedAccountId = '';
    @track selectedAccountName = '';
    @track opportunityTotal = null;
    @track opportunityError = null;
    @track isLoading = false;

    accounts;
    accountsError;

    @wire(getAccounts)
    wiredAccounts({ data, error }) {
        if (data) {
            this.accounts = data;
            this.accountsError = undefined;
        } else if (error) {
            this.accounts = undefined;
            this.accountsError = this._reduceError(error);
        }
    }

    get accountOptions() {
        if (!this.accounts) return [];
        return this.accounts.map(acc => ({
            label: acc.Name,
            value: acc.Id
        }));
    }

    get showTotal() {
        return !this.isLoading && this.opportunityTotal !== null && !this.opportunityError;
    }

    get formattedTotal() {
        if (this.opportunityTotal === null) return '';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2
        }).format(this.opportunityTotal);
    }

    handleAccountChange(event) {
        this.selectedAccountId = event.detail.value;
        const selected = this.accounts.find(acc => acc.Id === this.selectedAccountId);
        this.selectedAccountName = selected ? selected.Name : '';
        this._loadOpportunityTotal();
    }

    _loadOpportunityTotal() {
        if (!this.selectedAccountId) return;
        this.isLoading = true;
        this.opportunityTotal = null;
        this.opportunityError = null;

        getOpportunityTotal({ accountId: this.selectedAccountId })
            .then(result => {
                this.opportunityTotal = result;
                this.isLoading = false;
            })
            .catch(error => {
                this.opportunityError = this._reduceError(error);
                this.isLoading = false;
            });
    }

    _reduceError(error) {
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        return JSON.stringify(error);
    }
}