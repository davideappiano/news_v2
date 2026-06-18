@isTest
private class AccountResearchBatchTest {

    @isTest
    static void batch_processesAllOwnedAccounts() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'arb',
            Email = 'arb@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'BatchUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'arb-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;

        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accs.add(new Account(Name = 'Acct ' + i, OwnerId = u.Id, Industry = 'Tech'));
        }
        insert accs;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Status__c = 'Processing',
            Total_Accounts__c = 3,
            Processed_Accounts__c = 0
        );
        insert notw;

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        PromptTemplateService.setMock(mock);

        Test.startTest();
        Database.executeBatch(new AccountResearchBatch(notw.Id), 1);
        Test.stopTest();

        Integer childCount = [
            SELECT COUNT() FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id
        ];
        System.assertEquals(3, childCount, 'One AccountNews per owned account');

        NewsOfTheWeek__c after = [
            SELECT Processed_Accounts__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id
        ];
        System.assertEquals(3, after.Processed_Accounts__c, 'Counter incremented for each batch');
    }

    @isTest
    static void batch_logsErrorsAndContinues() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'arbf',
            Email = 'arbf@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'BatchFail',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'arbf-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;

        insert new Account(Name = 'Doomed', OwnerId = u.Id);

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Status__c = 'Processing',
            Total_Accounts__c = 1,
            Processed_Accounts__c = 0
        );
        insert notw;

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        mock.throwOnInvoke = true;
        PromptTemplateService.setMock(mock);

        Test.startTest();
        Database.executeBatch(new AccountResearchBatch(notw.Id), 1);
        Test.stopTest();

        NewsOfTheWeek__c after = [
            SELECT Error_Log__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id
        ];
        System.assert(after.Error_Log__c != null && after.Error_Log__c.contains('Mocked failure'),
            'Error captured in log');

        Integer childCount = [
            SELECT COUNT() FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id
        ];
        System.assertEquals(0, childCount, 'No children inserted on failure');
    }
}
