import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendToRep from '@salesforce/apex/NewsOfTheWeekController.sendToRep';

export default class SendToRepNewsOfTheWeek extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            const email = await sendToRep({ recordId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sent to rep',
                    message: `The PDF digest was emailed to ${email}.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            const message =
                error?.body?.message || error?.message || 'Unknown error sending the email.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not send',
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
