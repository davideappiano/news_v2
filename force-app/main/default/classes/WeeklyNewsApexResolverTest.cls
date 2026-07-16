@isTest
private class WeeklyNewsApexResolverTest {

    @isTest
    static void aggregate_returnsPartialSummariesWhenPresent() {
        User u = createSalesperson();
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            Partial_Summaries__c = '- Alpha raised a round (Alpha)\n\n- Beta named a CISO (Beta)'
        );
        insert notw;

        // Even with children present, partials take precedence for the reduce.
        Account a = new Account(Name = 'Alpha', OwnerId = u.Id);
        insert a;
        insert new AccountNews__c(Account__c = a.Id, News_Of_The_Week__c = notw.Id, News__c = '<p>ignored</p>');

        WeeklyNewsApexResolver.Request req = new WeeklyNewsApexResolver.Request();
        req.news = notw;

        List<WeeklyNewsApexResolver.Response> out = WeeklyNewsApexResolver.aggregate(
            new List<WeeklyNewsApexResolver.Request>{ req }
        );

        String prompt = out[0].prompt;
        System.assert(prompt.contains('Alpha raised a round'), 'Returns accumulated partials');
        System.assert(!prompt.contains('ignored'), 'Does not fall back to account blocks when partials exist');
    }

    @isTest
    static void aggregate_fallsBackToBlocksAndFiltersNoNews() {
        User u = createSalesperson();
        Account a1 = new Account(Name = 'Alpha', OwnerId = u.Id);
        Account a2 = new Account(Name = 'Quiet', OwnerId = u.Id);
        insert new List<Account>{ a1, a2 };

        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert notw;

        insert new List<AccountNews__c>{
            new AccountNews__c(Account__c = a1.Id, News_Of_The_Week__c = notw.Id, News__c = '<p>Alpha update</p>'),
            new AccountNews__c(Account__c = a2.Id, News_Of_The_Week__c = notw.Id, News__c = 'No news')
        };

        WeeklyNewsApexResolver.Request req = new WeeklyNewsApexResolver.Request();
        req.news = notw;

        List<WeeklyNewsApexResolver.Response> out = WeeklyNewsApexResolver.aggregate(
            new List<WeeklyNewsApexResolver.Request>{ req }
        );

        String prompt = out[0].prompt;
        System.assert(prompt.contains('## Alpha'), 'Material block present');
        System.assert(!prompt.contains('## Quiet'), 'No-news block filtered out (Solution 1)');
    }

    @isTest
    static void aggregate_handlesNoChildren() {
        User u = createSalesperson();
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert notw;

        WeeklyNewsApexResolver.Request req = new WeeklyNewsApexResolver.Request();
        req.news = notw;

        List<WeeklyNewsApexResolver.Response> out = WeeklyNewsApexResolver.aggregate(
            new List<WeeklyNewsApexResolver.Request>{ req }
        );

        System.assert(out[0].prompt.contains('No per-account research blocks'),
            'Empty-children fallback message returned');
    }

    @isTest
    static void aggregate_handlesNullNews() {
        WeeklyNewsApexResolver.Request req = new WeeklyNewsApexResolver.Request();
        req.news = null;

        List<WeeklyNewsApexResolver.Response> out = WeeklyNewsApexResolver.aggregate(
            new List<WeeklyNewsApexResolver.Request>{ req }
        );

        System.assertEquals('', out[0].prompt);
    }

    private static User createSalesperson() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'wnar',
            Email = 'wnar@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Resolver',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'wnar-' + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }
}
