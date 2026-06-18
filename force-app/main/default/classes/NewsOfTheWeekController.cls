public with sharing class NewsOfTheWeekController {

    public class LaunchResult {
        @AuraEnabled public Integer accountCount;
        @AuraEnabled public String message;
        public LaunchResult(Integer accountCount, String message) {
            this.accountCount = accountCount;
            this.message = message;
        }
    }

    @AuraEnabled
    public static LaunchResult launch(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A NewsOfTheWeek record id is required.');
        }

        NewsOfTheWeek__c notw = [
            SELECT Id, Salesperson__c, Status__c
            FROM NewsOfTheWeek__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (notw.Salesperson__c == null) {
            throw new AuraHandledException('Salesperson must be set before launching.');
        }

        if (notw.Status__c == 'Processing') {
            throw new AuraHandledException('A run is already in progress for this record.');
        }

        Integer accountCount = [
            SELECT COUNT()
            FROM Account
            WHERE OwnerId = :notw.Salesperson__c
        ];

        if (accountCount == 0) {
            throw new AuraHandledException('The selected Salesperson does not own any accounts.');
        }

        // Wipe prior children so the new run starts fresh.
        delete [SELECT Id FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id];

        notw.Status__c = 'Processing';
        notw.Run_Date__c = Date.today();
        notw.Error_Log__c = null;
        notw.News_Head__c = null;
        notw.Total_Accounts__c = accountCount;
        notw.Processed_Accounts__c = 0;
        update notw;

        // Batchable Apex: each account becomes one batch (size 1) so each
        // prompt-template callout runs in its own transaction. The batch's
        // finish() method enqueues the WeeklySummaryQueueable automatically.
        Database.executeBatch(new AccountResearchBatch(notw.Id), AccountResearchBatch.DEFAULT_BATCH_SIZE);

        return new LaunchResult(accountCount, 'Background research started.');
    }

    /**
     * Wipe a NewsOfTheWeek__c run back to a clean Draft state.
     */
    @AuraEnabled
    public static Integer reset(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A NewsOfTheWeek record id is required.');
        }

        NewsOfTheWeek__c notw = [
            SELECT Id, Status__c
            FROM NewsOfTheWeek__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (notw.Status__c == 'Processing') {
            throw new AuraHandledException(
                'Cannot reset while a run is Processing. Wait for it to finish or fail first.'
            );
        }

        List<AccountNews__c> children = [
            SELECT Id FROM AccountNews__c WHERE News_Of_The_Week__c = :recordId
        ];
        Integer deleted = children.size();
        if (deleted > 0) {
            delete children;
        }

        notw.News_Head__c = null;
        notw.Error_Log__c = null;
        notw.Run_Date__c = null;
        notw.Status__c = 'Draft';
        notw.Total_Accounts__c = null;
        notw.Processed_Accounts__c = null;
        update notw;

        return deleted;
    }
}
