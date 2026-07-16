import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import rerunSummary from '@salesforce/apex/NewsOfTheWeekController.rerunSummary';

export default class RerunSummaryNewsOfTheWeek extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            await rerunSummary({ recordId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Summary re-run started',
                    message: 'Re-summarizing the existing Account News in the background. The page will refresh when complete.',
                    variant: 'success'
                })
            );
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (error) {
            const message =
                error?.body?.message || error?.message || 'Unknown error re-running the summary.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not re-run summary',
                    message,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
}
