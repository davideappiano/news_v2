@isTest
private class AccountResearchBatchTest {

    @isTest
    static void batch_processesAllAccountsInPage() {
        User u = createSalesperson('arb');
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accs.add(new Account(Name = 'Acct ' + i, OwnerId = u.Id, Industry = 'Tech'));
        }
        insert accs;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Status__c = 'Processing',
            Total_Accounts__c = 3,
            Processed_Accounts__c = 0,
            Active_Streams__c = 1
        );
        insert notw;

        List<Id> streamIds = new List<Id>();
        for (Account a : accs) streamIds.add(a.Id);

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        PromptTemplateService.setMock(mock);

        Test.startTest();
        Database.executeBatch(new AccountResearchBatch(notw.Id, streamIds, 0, 25), 1);
        Test.stopTest();

        Integer childCount = [
            SELECT COUNT() FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id
        ];
        System.assertEquals(3, childCount, 'One AccountNews per account in the page');

        NewsOfTheWeek__c after = [
            SELECT Processed_Accounts__c, Active_Streams__c
            FROM NewsOfTheWeek__c
            WHERE Id = :notw.Id
        ];
        System.assertEquals(3, after.Processed_Accounts__c, 'Counter incremented for each');
        System.assertEquals(0, after.Active_Streams__c, 'Single-stream finish() decremented to 0');
    }

    @isTest
    static void batch_logsErrorAndStillDecrementsStreams() {
        User u = createSalesperson('arbf');
        Account a = new Account(Name = 'Doomed', OwnerId = u.Id);
        insert a;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Status__c = 'Processing',
            Total_Accounts__c = 1,
            Processed_Accounts__c = 0,
            Active_Streams__c = 1
        );
        insert notw;

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        mock.throwOnInvoke = true;
        PromptTemplateService.setMock(mock);

        Test.startTest();
        Database.executeBatch(new AccountResearchBatch(notw.Id, new List<Id>{ a.Id }, 0, 25), 1);
        Test.stopTest();

        NewsOfTheWeek__c after = [
            SELECT Error_Log__c, Active_Streams__c
            FROM NewsOfTheWeek__c
            WHERE Id = :notw.Id
        ];
        System.assert(after.Error_Log__c != null && after.Error_Log__c.contains('Mocked failure'),
            'Error captured');
        System.assertEquals(0, after.Active_Streams__c, 'Stream still decrements on failure');

        Integer childCount = [
            SELECT COUNT() FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id
        ];
        System.assertEquals(0, childCount, 'No children inserted on failure');
    }

    private static User createSalesperson(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias,
            Email = alias + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = alias + '-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }
}
