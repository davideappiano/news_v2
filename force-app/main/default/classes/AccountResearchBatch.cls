/**
 * Per-account research using chained, paginated Batchable Apex.
 *
 * Architecture:
 *   - The controller fans out STREAM_COUNT (=5, the org's concurrent-batch
 *     ceiling) parallel batch jobs at launch.
 *   - Each stream owns a fixed slice of account ids assigned round-robin.
 *   - A stream processes its accounts one PAGE at a time. After each page,
 *     finish() either chains the next page or — when this stream has run
 *     out of pages — decrements NewsOfTheWeek__c.Active_Streams__c.
 *   - Whichever stream brings Active_Streams__c to 0 enqueues the summary.
 *
 * This sidesteps the "Maximum stack depth" the Queueable approach hit, gives
 * 5x the throughput of a single batch job, and scales to portfolios of any
 * size by chaining pages without rebuilding state in the controller.
 */
public with sharing class AccountResearchBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    @TestVisible
    private static final String TEMPLATE_DEVELOPER_NAME = 'Account_News_Research_PT';

    /** Max parallel streams. Salesforce caps concurrent batch jobs at 5. */
    public static final Integer STREAM_COUNT = 5;

    /** Account ids per chained job. Smaller pages = more chain hops, but lighter per-job state. */
    public static final Integer DEFAULT_PAGE_SIZE = 25;

    /** Records per execute() transaction within a page. 1 = one callout per transaction (safest isolation). */
    public static final Integer EXECUTE_BATCH_SIZE = 1;

    private final Id newsOfTheWeekId;
    private final List<Id> streamAccountIds;
    private final Integer pageIndex;
    private final Integer pageSize;

    public AccountResearchBatch(
        Id newsOfTheWeekId,
        List<Id> streamAccountIds,
        Integer pageIndex,
        Integer pageSize
    ) {
        this.newsOfTheWeekId = newsOfTheWeekId;
        this.streamAccountIds = streamAccountIds == null ? new List<Id>() : streamAccountIds;
        this.pageIndex = pageIndex == null ? 0 : pageIndex;
        this.pageSize = pageSize == null ? DEFAULT_PAGE_SIZE : pageSize;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Integer offset = pageIndex * pageSize;
        Integer endExclusive = Math.min(offset + pageSize, streamAccountIds.size());
        List<Id> pageIds = new List<Id>();
        for (Integer i = offset; i < endExclusive; i++) {
            pageIds.add(streamAccountIds[i]);
        }
        return Database.getQueryLocator([
            SELECT Id, Name, Industry, Website, BillingCity, BillingCountry, Description
            FROM Account
            WHERE Id IN :pageIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<AccountNews__c> toInsert = new List<AccountNews__c>();
        for (SObject so : scope) {
            Account acct = (Account) so;
            try {
                Map<String, Object> inputs = new Map<String, Object>{
                    'Input:account' => acct
                };
                PromptTemplateService.PromptResult result =
                    PromptTemplateService.getInstance().invoke(TEMPLATE_DEVELOPER_NAME, inputs);

                toInsert.add(new AccountNews__c(
                    Account__c = acct.Id,
                    News_Of_The_Week__c = newsOfTheWeekId,
                    News__c = String.isBlank(result.text) ? '<p><em>No relevant news found.</em></p>' : result.text,
                    Sources__c = result.citations
                ));
            } catch (Exception e) {
                appendError(acct.Id, e);
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        bumpProcessedCounter(scope.size());
    }

    public void finish(Database.BatchableContext bc) {
        Integer nextOffset = (pageIndex + 1) * pageSize;
        if (nextOffset < streamAccountIds.size()) {
            // More pages in this stream — chain another batch job for the next page.
            Database.executeBatch(
                new AccountResearchBatch(newsOfTheWeekId, streamAccountIds, pageIndex + 1, pageSize),
                EXECUTE_BATCH_SIZE
            );
        } else {
            // This stream is exhausted. Atomically decrement Active_Streams__c;
            // whichever stream brings it to 0 fires the summary.
            decrementStreamsAndMaybeFireSummary();
        }
    }

    private void decrementStreamsAndMaybeFireSummary() {
        try {
            NewsOfTheWeek__c parent = [
                SELECT Id, Active_Streams__c
                FROM NewsOfTheWeek__c
                WHERE Id = :newsOfTheWeekId
                FOR UPDATE
            ];
            Decimal current = parent.Active_Streams__c == null ? 0 : parent.Active_Streams__c;
            parent.Active_Streams__c = current - 1;
            update parent;

            if (parent.Active_Streams__c <= 0) {
                System.enqueueJob(new WeeklySummaryQueueable(newsOfTheWeekId));
            }
        } catch (Exception e) {
            appendError(null, e);
        }
    }

    private void bumpProcessedCounter(Integer delta) {
        try {
            NewsOfTheWeek__c parent = [
                SELECT Id, Processed_Accounts__c
                FROM NewsOfTheWeek__c
                WHERE Id = :newsOfTheWeekId
                FOR UPDATE
            ];
            Decimal current = parent.Processed_Accounts__c == null ? 0 : parent.Processed_Accounts__c;
            parent.Processed_Accounts__c = current + delta;
            update parent;
        } catch (Exception ignored) {
            // Don't fail the batch over a progress-counter update.
        }
    }

    private void appendError(Id accId, Exception e) {
        try {
            NewsOfTheWeek__c parent = [
                SELECT Id, Error_Log__c
                FROM NewsOfTheWeek__c
                WHERE Id = :newsOfTheWeekId
                LIMIT 1
            ];
            String prior = parent.Error_Log__c == null ? '' : parent.Error_Log__c + '\n';
            String accLabel = accId == null ? '<stream>' : String.valueOf(accId);
            String entry = '[' + System.now().format() + '] Account ' + accLabel
                + ' - ' + e.getTypeName() + ': ' + e.getMessage();
            parent.Error_Log__c = (prior + entry).left(32768);
            update parent;
        } catch (Exception ignored) {
            // Don't let logging failures break the run.
        }
    }
}
