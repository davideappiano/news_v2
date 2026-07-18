@isTest
private class GeneratePdfQueueableTest {

    @isTest
    static void execute_generatesPdfForRun() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'gpq',
            Email = 'gpq@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Pdf',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'gpq-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;

        NewsOfTheWeek__c config = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert config;
        NewsRun__c run = new NewsRun__c(
            News_Of_The_Week__c = config.Id,
            Salesperson__c = u.Id,
            News_Head__c = '<h2>Weekly Brief</h2><p>Signals.</p>',
            Run_Date__c = Date.today(),
            Status__c = 'Complete'
        );
        insert run;

        Test.startTest();
        new GeneratePdfQueueable(run.Id).execute(null);
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :run.Id],
            'PDF attached to the run by the queueable');
    }

    @isTest
    static void execute_swallowsErrorWhenNewsHeadEmpty() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'gpq2',
            Email = 'gpq2@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Pdf',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'gpq2-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;

        NewsOfTheWeek__c config = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert config;
        NewsRun__c run = new NewsRun__c(
            News_Of_The_Week__c = config.Id,
            Salesperson__c = u.Id,
            Run_Date__c = Date.today(),
            Status__c = 'Complete'
        );
        insert run;

        Test.startTest();
        new GeneratePdfQueueable(run.Id).execute(null); // must not throw
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :run.Id],
            'No PDF when News Head is empty; error swallowed');
    }
}
