@isTest
private class WeeklySummaryQueueableTest {

    @isTest
    static void execute_summarizesChildrenIntoNewsHead() {
        User u = createSalesperson();
        Account a = new Account(Name = 'Delta Inc', OwnerId = u.Id);
        insert a;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        insert new AccountNews__c(
            Account__c = a.Id,
            News_Of_The_Week__c = notw.Id,
            News__c = '<p>Acquired Foo Inc.</p>'
        );

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        mock.resultByTemplate.put('Weekly_News_Summary_PT',
            new PromptTemplateService.PromptResult('<h2>Weekly Brief</h2><p>Delta acquired Foo.</p>', ''));
        PromptTemplateService.setMock(mock);

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Status__c, News_Head__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assertEquals('Complete', after.Status__c);
        System.assert(after.News_Head__c.contains('Weekly Brief'), 'News head populated');

        List<NewsRun__c> archives = [
            SELECT News_Head__c, Status__c, News_Of_The_Week__c
            FROM NewsRun__c
            WHERE News_Of_The_Week__c = :notw.Id
        ];
        System.assertEquals(1, archives.size(), 'A NewsRun snapshot is created on success');
        System.assertEquals('Complete', archives[0].Status__c);
        System.assert(archives[0].News_Head__c.contains('Weekly Brief'), 'Snapshot captured the newsletter');

        // Children moved off the config and onto the archived run.
        System.assertEquals(0,
            [SELECT COUNT() FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id],
            'No AccountNews left on the config after archive');
        System.assertEquals(1,
            [SELECT COUNT() FROM AccountNews__c WHERE News_Run__c = :archives[0].Id],
            'AccountNews reparented to the NewsRun');
    }

    @isTest
    static void execute_marksFailedWhenNoChildren() {
        User u = createSalesperson();
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        PromptTemplateService.setMock(new PromptTemplateServiceMock());

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Status__c, Error_Log__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assertEquals('Failed', after.Status__c);
        System.assert(after.Error_Log__c.contains('nothing to summarize'));
        System.assertEquals(0, [SELECT COUNT() FROM NewsRun__c WHERE News_Of_The_Week__c = :notw.Id],
            'No archive on failure');
    }

    @isTest
    static void execute_marksFailedWhenTemplateThrows() {
        User u = createSalesperson();
        Account a = new Account(Name = 'Epsilon SA', OwnerId = u.Id);
        insert a;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        insert new AccountNews__c(
            Account__c = a.Id,
            News_Of_The_Week__c = notw.Id,
            News__c = '<p>Something.</p>'
        );

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        mock.throwOnInvoke = true;
        PromptTemplateService.setMock(mock);

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Status__c, Error_Log__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assertEquals('Failed', after.Status__c);
        System.assert(after.Error_Log__c.contains('Summary step failed'));
        System.assertEquals(0, [SELECT COUNT() FROM NewsRun__c WHERE News_Of_The_Week__c = :notw.Id],
            'No archive when the summary template throws');
    }

    private static User createSalesperson() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'wsq',
            Email = 'wsq@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Summary',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'wsq-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }
}
