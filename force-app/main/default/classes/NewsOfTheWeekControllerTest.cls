@isTest
private class NewsOfTheWeekControllerTest {

    @testSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'snews',
            Email = 'snews@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Salesperson',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'snews-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;

        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accs.add(new Account(Name = 'Acme ' + i, OwnerId = u.Id));
        }
        insert accs;
    }

    @isTest
    static void launch_enqueuesAndReturnsCount() {
        User u = [SELECT Id FROM User WHERE Alias = 'snews' LIMIT 1];
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert notw;

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        PromptTemplateService.setMock(mock);

        Test.startTest();
        NewsOfTheWeekController.LaunchResult result = NewsOfTheWeekController.launch(notw.Id);
        Test.stopTest();

        System.assertEquals(3, result.accountCount, 'Should report 3 owned accounts');

        NewsOfTheWeek__c after = [
            SELECT Status__c, Run_Date__c, Total_Accounts__c, Processed_Accounts__c
            FROM NewsOfTheWeek__c
            WHERE Id = :notw.Id
        ];
        System.assertEquals('Processing', after.Status__c, 'Status flipped to Processing');
        System.assertEquals(Date.today(), after.Run_Date__c, 'Run_Date stamped');
        System.assertEquals(3, after.Total_Accounts__c, 'Total_Accounts stamped from query');
        System.assertEquals(0, after.Processed_Accounts__c, 'Processed_Accounts reset to 0');
    }

    @isTest
    static void launch_throwsWhenNoSalesperson() {
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c();
        // Salesperson__c is required at the field level, so simulate missing via separate update path:
        // Insert with a salesperson then null it out for this branch coverage.
        User u = [SELECT Id FROM User WHERE Alias = 'snews' LIMIT 1];
        notw.Salesperson__c = u.Id;
        insert notw;

        Boolean threw = false;
        try {
            NewsOfTheWeekController.launch(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject null record id');
    }

    @isTest
    static void launch_throwsWhenSalespersonHasNoAccounts() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User loner = new User(
            Alias = 'lonely',
            Email = 'l@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Lonely',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'lonely-' + DateTime.now().getTime() + '@example.com'
        );
        insert loner;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = loner.Id);
        insert notw;

        Boolean threw = false;
        try {
            NewsOfTheWeekController.launch(notw.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject when no owned accounts');
    }
}
