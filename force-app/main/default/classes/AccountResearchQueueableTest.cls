@isTest
private class AccountResearchQueueableTest {

    @isTest
    static void execute_insertsAccountNewsAndIncrementsCounter() {
        User u = createSalesperson();
        Account a = new Account(Name = 'Beta Corp', OwnerId = u.Id, Industry = 'Technology');
        insert a;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Status__c = 'Processing',
            Total_Accounts__c = 1,
            Processed_Accounts__c = 0
        );
        insert notw;

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        PromptTemplateService.setMock(mock);

        Test.startTest();
        new AccountResearchQueueable(notw.Id, a.Id, new List<Id>()).execute(null);
        Test.stopTest();

        List<AccountNews__c> children = [
            SELECT Account__c, News__c
            FROM AccountNews__c
            WHERE News_Of_The_Week__c = :notw.Id
        ];
        System.assertEquals(1, children.size(), 'One AccountNews inserted');
        System.assertEquals(a.Id, children[0].Account__c);
        System.assertEquals(1, mock.calls.size(), 'Prompt template called exactly once');

        NewsOfTheWeek__c after = [
            SELECT Processed_Accounts__c
            FROM NewsOfTheWeek__c
            WHERE Id = :notw.Id
        ];
        System.assertEquals(1, after.Processed_Accounts__c, 'Counter incremented');
    }

    @isTest
    static void execute_logsErrorButStillIncrementsCounter() {
        User u = createSalesperson();
        Account a = new Account(Name = 'Gamma Ltd', OwnerId = u.Id);
        insert a;

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
        new AccountResearchQueueable(notw.Id, a.Id, new List<Id>()).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [
            SELECT Error_Log__c, Processed_Accounts__c
            FROM NewsOfTheWeek__c
            WHERE Id = :notw.Id
        ];
        System.assert(after.Error_Log__c != null && after.Error_Log__c.contains('Mocked failure'),
            'Error captured in log');
        System.assertEquals(1, after.Processed_Accounts__c,
            'Counter still increments on failure so the summary can fire');

        List<AccountNews__c> children = [SELECT Id FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id];
        System.assertEquals(0, children.size(), 'No AccountNews inserted on failure');
    }

    private static User createSalesperson() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'arq',
            Email = 'arq@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Researcher',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'arq-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }
}
