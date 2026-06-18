/**
 * Per-account research, run as Batchable Apex. Replaces the Queueable
 * fan-out — Queueable was hitting "Maximum stack depth has been reached"
 * inside the ConnectApi.EinsteinLLM callout. Batchable uses a different
 * async container that side-steps that issue, and its finish() lifecycle
 * fires the summary automatically without counter coordination.
 *
 * Batch size = 1: each prompt-template callout runs in its own transaction,
 * isolating failures and giving the platform's web grounding maximum time
 * per account. The platform processes up to 5 concurrent batch executions
 * by default, so with 69 accounts the wall-clock is ~ceil(69/5) × 30s.
 */
public with sharing class AccountResearchBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    @TestVisible
    private static final String TEMPLATE_DEVELOPER_NAME = 'Account_News_Research_PT';

    @TestVisible
    public static final Integer DEFAULT_BATCH_SIZE = 1;

    private final Id newsOfTheWeekId;

    public AccountResearchBatch(Id newsOfTheWeekId) {
        this.newsOfTheWeekId = newsOfTheWeekId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        NewsOfTheWeek__c notw = [
            SELECT Salesperson__c
            FROM NewsOfTheWeek__c
            WHERE Id = :newsOfTheWeekId
            LIMIT 1
        ];
        Id salespersonId = notw.Salesperson__c;
        return Database.getQueryLocator([
            SELECT Id, Name, Industry, Website, BillingCity, BillingCountry, Description
            FROM Account
            WHERE OwnerId = :salespersonId
            ORDER BY Name ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<AccountNews__c> toInsert = new List<AccountNews__c>();
        for (SObject so : scope) {
            Account acct = (Account) so;
            try {
                // Key matches the prompt template input's referenceName (Input:account).
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
        // The whole batch finished — fire the summary even if some accounts
        // failed; the summary template will report on whatever children exist.
        System.enqueueJob(new WeeklySummaryQueueable(newsOfTheWeekId));
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
            String entry = '[' + System.now().format() + '] Account ' + accId
                + ' - ' + e.getTypeName() + ': ' + e.getMessage();
            parent.Error_Log__c = (prior + entry).left(32768);
            update parent;
        } catch (Exception ignored) {
            // Don't let logging failures break the run.
        }
    }
}
