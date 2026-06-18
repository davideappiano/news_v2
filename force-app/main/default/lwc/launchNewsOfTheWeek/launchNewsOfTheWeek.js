import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import launch from '@salesforce/apex/NewsOfTheWeekController.launch';

export default class LaunchNewsOfTheWeek extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            const result = await launch({ recordId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'News research started',
                    message: `Researching ${result.accountCount} account(s) in the background. The page will refresh when complete.`,
                    variant: 'success'
                })
            );
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (error) {
            const message =
                error?.body?.message || error?.message || 'Unknown error launching the run.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not start research',
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
