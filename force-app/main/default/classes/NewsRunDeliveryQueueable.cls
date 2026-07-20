/**
 * Finalizes a NewsRun__c: optionally (re)generates the PDF, then emails it to
 * the salesperson. Merges the former GeneratePdfQueueable + SendToRepQueueable.
 *
 *  - Auto pipeline (after a run is archived): new NewsRunDeliveryQueueable(runId, true)
 *      → renders the PDF, attaches it, then sends the email.
 *  - Manual "Send to Rep" button: new NewsRunDeliveryQueueable(runId, false)
 *      → skips generation (PDF already exists) and just sends.
 *
 * One transaction is safe: getContentAsPDF() (callout-like) runs BEFORE any DML,
 * then the PDF is saved, then sendEmail() (not a callout) runs — so there's no
 * DML-before-callout violation. Runs async so the email goes out in a system
 * context. Failures are logged to the run's config, never rethrown.
 */
public with sharing class NewsRunDeliveryQueueable implements Queueable, Database.AllowsCallouts {

    private final Id newsRunId;
    private final Boolean generatePdf;

    public NewsRunDeliveryQueueable(Id newsRunId, Boolean generatePdf) {
        this.newsRunId = newsRunId;
        this.generatePdf = generatePdf;
    }

    public void execute(QueueableContext ctx) {
        if (generatePdf) {
            try {
                NewsOfTheWeekController.generatePdfForRun(newsRunId);
            } catch (Exception e) {
                // No PDF → nothing to send. Log and stop.
                logError('Auto PDF failed: ' + e.getMessage());
                return;
            }
        }

        try {
            NewsOfTheWeekController.deliverToRep(newsRunId);
        } catch (Exception e) {
            logError('Send to rep failed: ' + e.getMessage());
        }
    }

    /** Best-effort: record a failure on the run's config so it's visible. */
    private void logError(String message) {
        try {
            NewsRun__c run = [
                SELECT News_Of_The_Week__c FROM NewsRun__c WHERE Id = :newsRunId LIMIT 1
            ];
            if (run.News_Of_The_Week__c == null) {
                return;
            }
            NewsOfTheWeek__c cfg = [
                SELECT Id, Error_Log__c FROM NewsOfTheWeek__c
                WHERE Id = :run.News_Of_The_Week__c LIMIT 1
            ];
            String prior = cfg.Error_Log__c == null ? '' : cfg.Error_Log__c + '\n';
            cfg.Error_Log__c = (prior + '[' + System.now().format() + '] '
                + message + ' (run ' + newsRunId + ')').left(32768);
            update cfg;
        } catch (Exception ignored) {
            // swallow
        }
    }
}
