/**
 * Per-account worker. The controller fans out up to 50 of these in parallel
 * (the platform's `System.enqueueJob`-per-transaction limit). For portfolios
 * larger than 50, each worker carries a "tail" of additional account ids that
 * it processes one at a time — chaining itself through the tail keeps every
 * worker's processing serial, but the 50 worker streams run concurrently.
 *
 * Counter coordination: each worker increments
 * NewsOfTheWeek__c.Processed_Accounts__c with a `FOR UPDATE` row lock so
 * concurrent increments are atomic. Whichever worker pushes the counter to
 * Total_Accounts__c enqueues the WeeklySummaryQueueable.
 */
public with sharing class AccountResearchQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final String TEMPLATE_DEVELOPER_NAME = 'Account_News_Research_PT';

    private final Id newsOfTheWeekId;
    private final Id accountId;
    private final List<Id> tail;

    public AccountResearchQueueable(Id newsOfTheWeekId, Id accountId, List<Id> tail) {
        this.newsOfTheWeekId = newsOfTheWeekId;
        this.accountId = accountId;
        this.tail = tail == null ? new List<Id>() : new List<Id>(tail);
    }

    public void execute(QueueableContext ctx) {
        try {
            researchAccount();
        } catch (Exception e) {
            appendError(accountId, e);
        }

        Boolean lastOne = incrementAndCheckCompletion();

        // Apex allows max 1 chained enqueueJob per Queueable execution.
        // - If we still have tail items, continue this chain.
        // - Otherwise, if we were the last worker globally, fire the summary.
        // - Otherwise nothing — another worker is still in flight.
        if (!tail.isEmpty()) {
            Id nextId = tail.remove(0);
            if (!Test.isRunningTest()) {
                System.enqueueJob(new AccountResearchQueueable(newsOfTheWeekId, nextId, tail));
            }
        } else if (lastOne && !Test.isRunningTest()) {
            System.enqueueJob(new WeeklySummaryQueueable(newsOfTheWeekId));
        }
    }

    private void researchAccount() {
        Account acct = [
            SELECT Id, Name, Industry, Website, BillingCity, BillingCountry, Description
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        // Key matches the prompt template input's referenceName (Input:account).
        Map<String, Object> inputs = new Map<String, Object>{
            'Input:account' => acct
        };

        PromptTemplateService.PromptResult result =
            PromptTemplateService.getInstance().invoke(TEMPLATE_DEVELOPER_NAME, inputs);

        AccountNews__c child = new AccountNews__c(
            Account__c = acct.Id,
            News_Of_The_Week__c = newsOfTheWeekId,
            News__c = String.isBlank(result.text) ? '<p><em>No relevant news found.</em></p>' : result.text,
            Sources__c = result.citations
        );
        insert child;
    }

    /**
     * `FOR UPDATE` serialises concurrent workers so the increment is atomic.
     * Returns true iff this worker was the one to complete the run.
     */
    private Boolean incrementAndCheckCompletion() {
        try {
            NewsOfTheWeek__c parent = [
                SELECT Id, Total_Accounts__c, Processed_Accounts__c
                FROM NewsOfTheWeek__c
                WHERE Id = :newsOfTheWeekId
                FOR UPDATE
            ];
            Decimal current = parent.Processed_Accounts__c == null ? 0 : parent.Processed_Accounts__c;
            Decimal total = parent.Total_Accounts__c == null ? 0 : parent.Total_Accounts__c;
            parent.Processed_Accounts__c = current + 1;
            update parent;
            return parent.Processed_Accounts__c >= total;
        } catch (Exception e) {
            // If the counter update itself fails, log and fall back to NOT firing
            // the summary from this worker — better to leave Status='Processing'
            // than fire the summary twice.
            appendError(accountId, e);
            return false;
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
