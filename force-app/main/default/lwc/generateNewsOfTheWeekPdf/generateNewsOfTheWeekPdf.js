import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import generatePdf from '@salesforce/apex/NewsOfTheWeekController.generatePdf';

export default class GenerateNewsOfTheWeekPdf extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            const result = await generatePdf({ recordId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'PDF generated',
                    message: `${result.fileName} has been attached to this record.`,
                    variant: 'success'
                })
            );
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (error) {
            const message =
                error?.body?.message || error?.message || 'Unknown error generating the PDF.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not generate PDF',
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
