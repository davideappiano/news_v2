/**
 * Generates the PDF for a completed NewsRun__c in its own transaction.
 *
 * PageReference.getContentAsPDF() behaves like a callout and throws
 * "uncommitted work pending" if DML preceded it. The archive step
 * (WeeklySummaryQueueable.archiveRun) has already done DML, so it enqueues this
 * job to render + attach the PDF in a clean transaction right after the run
 * is archived.
 */
public with sharing class GeneratePdfQueueable implements Queueable, Database.AllowsCallouts {

    private final Id newsRunId;

    public GeneratePdfQueueable(Id newsRunId) {
        this.newsRunId = newsRunId;
    }

    public void execute(QueueableContext ctx) {
        try {
            NewsOfTheWeekController.generatePdfForRun(newsRunId);
        } catch (Exception e) {
            // Best-effort: log to the run's config error log, never rethrow —
            // a PDF failure shouldn't disturb the already-complete run.
            try {
                NewsRun__c run = [
                    SELECT News_Of_The_Week__c FROM NewsRun__c WHERE Id = :newsRunId LIMIT 1
                ];
                if (run.News_Of_The_Week__c != null) {
                    NewsOfTheWeek__c cfg = [
                        SELECT Id, Error_Log__c FROM NewsOfTheWeek__c
                        WHERE Id = :run.News_Of_The_Week__c LIMIT 1
                    ];
                    String prior = cfg.Error_Log__c == null ? '' : cfg.Error_Log__c + '\n';
                    cfg.Error_Log__c = (prior + '[' + System.now().format() + '] Auto PDF failed for '
                        + newsRunId + ': ' + e.getMessage()).left(32768);
                    update cfg;
                }
            } catch (Exception ignored) {
                // swallow
            }
        }
    }
}
