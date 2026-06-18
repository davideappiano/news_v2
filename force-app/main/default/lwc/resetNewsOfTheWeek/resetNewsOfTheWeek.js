import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import reset from '@salesforce/apex/NewsOfTheWeekController.reset';

export default class ResetNewsOfTheWeek extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            const confirmed = await LightningConfirm.open({
                message:
                    'This will delete every Account News record attached to this run and clear the News Head. This cannot be undone. Continue?',
                variant: 'header',
                label: 'Reset News Of The Week'
            });

            if (!confirmed) {
                this.dispatchEvent(new CloseActionScreenEvent());
                return;
            }

            const deletedCount = await reset({ recordId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reset complete',
                    message: `Deleted ${deletedCount} Account News record(s) and cleared the newsletter.`,
                    variant: 'success'
                })
            );
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (error) {
            const message =
                error?.body?.message || error?.message || 'Unknown error during reset.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reset failed',
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
