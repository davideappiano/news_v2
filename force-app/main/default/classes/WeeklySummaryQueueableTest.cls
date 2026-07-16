@isTest
private class WeeklySummaryQueueableTest {

    @isTest
    static void map_summarizesChunkIntoPartials() {
        User u = createSalesperson();
        Account a = new Account(Name = 'Delta Inc', OwnerId = u.Id);
        insert a;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        insert new AccountNews__c(
            Account__c = a.Id,
            News_Of_The_Week__c = notw.Id,
            News__c = '<p>Delta acquired Foo Inc.</p>'
        );

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        mock.resultByTemplate.put('Weekly_News_Chunk_PT',
            new PromptTemplateService.PromptResult('- Delta acquired Foo (Delta Inc)', ''));
        PromptTemplateService.setMock(mock);

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id, 0, false).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Partial_Summaries__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assert(after.Partial_Summaries__c.contains('Delta acquired Foo'),
            'Chunk partial appended to Partial_Summaries__c');
    }

    @isTest
    static void map_skipsNoNewsBlocks() {
        User u = createSalesperson();
        Account a = new Account(Name = 'Quiet Co', OwnerId = u.Id);
        insert a;

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        insert new AccountNews__c(
            Account__c = a.Id,
            News_Of_The_Week__c = notw.Id,
            News__c = 'No news'
        );

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        PromptTemplateService.setMock(mock);

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id, 0, false).execute(null);
        Test.stopTest();

        // Chunk text was empty → no template call, no partial written.
        System.assertEquals(0, mock.calls.size(), 'No template call for an all-No-news chunk');
        NewsOfTheWeek__c after = [SELECT Partial_Summaries__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assert(String.isBlank(after.Partial_Summaries__c), 'Nothing appended');
    }

    @isTest
    static void reduce_writesNewsHeadFromPartials() {
        User u = createSalesperson();
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Status__c = 'Processing',
            Partial_Summaries__c = '- Delta acquired Foo (Delta Inc)\n\n- Epsilon named a new CEO (Epsilon SA)'
        );
        insert notw;

        PromptTemplateServiceMock mock = new PromptTemplateServiceMock();
        mock.resultByTemplate.put('Weekly_News_Summary_PT',
            new PromptTemplateService.PromptResult('<h2>Weekly Brief</h2><p>Two moves this week.</p>', ''));
        PromptTemplateService.setMock(mock);

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id, 0, true).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Status__c, News_Head__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assertEquals('Complete', after.Status__c);
        System.assert(after.News_Head__c.contains('Weekly Brief'), 'News head populated from reduce');
    }

    @isTest
    static void reduce_completesWithFallbackWhenNoPartials() {
        User u = createSalesperson();
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        PromptTemplateService.setMock(new PromptTemplateServiceMock());

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id, 0, true).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Status__c, News_Head__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assertEquals('Complete', after.Status__c);
        System.assert(after.News_Head__c.contains('No commercially relevant news'),
            'Fallback message when there are no partials');
    }

    @isTest
    static void map_marksFailedWhenNoChildren() {
        User u = createSalesperson();
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id, Status__c = 'Processing');
        insert notw;

        PromptTemplateService.setMock(new PromptTemplateServiceMock());

        Test.startTest();
        new WeeklySummaryQueueable(notw.Id, 0, false).execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [SELECT Status__c, Error_Log__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id];
        System.assertEquals('Failed', after.Status__c);
        System.assert(after.Error_Log__c.contains('nothing to summarize'));
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
