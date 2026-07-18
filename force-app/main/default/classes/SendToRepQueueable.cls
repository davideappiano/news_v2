/**
 * Sends the News Run PDF to the salesperson in an async (system) context.
 *
 * The interactive sendToRep action validates and enqueues this job. Running the
 * Messaging.sendEmail here — rather than in the user's synchronous request —
 * lets the email through when org deliverability is set to "System email only",
 * which otherwise blocks user-context single-email sends (NO_SINGLE_MAIL_PERMISSION).
 */
public with sharing class SendToRepQueueable implements Queueable {

    private final Id newsRunId;

    public SendToRepQueueable(Id newsRunId) {
        this.newsRunId = newsRunId;
    }

    public void execute(QueueableContext ctx) {
        try {
            NewsOfTheWeekController.deliverToRep(newsRunId);
        } catch (Exception e) {
            logError(e.getMessage());
        }
    }

    /** Best-effort: record a send failure on the run's config so it's visible. */
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
            cfg.Error_Log__c = (prior + '[' + System.now().format() + '] Send to rep failed for '
                + newsRunId + ': ' + message).left(32768);
            update cfg;
        } catch (Exception ignored) {
            // swallow
        }
    }
}
