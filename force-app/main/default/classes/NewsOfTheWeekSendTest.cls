@isTest
private class NewsOfTheWeekSendTest {

    @isTest
    static void generatePdf_attachesPdfToRun() {
        User u = createSalesperson('gpdf', 'gpdf@example.com');
        NewsRun__c run = newRun(u, '<h2>Weekly Brief</h2><p>Signals.</p>');

        Test.startTest();
        NewsOfTheWeekController.PdfResult res = NewsOfTheWeekController.generatePdf(run.Id);
        Test.stopTest();

        System.assertNotEquals(null, res.contentDocumentId, 'A PDF document was created');
        System.assertEquals(1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :run.Id],
            'PDF linked to the NewsRun');
    }

    @isTest
    static void generatePdf_throwsWhenNewsHeadEmpty() {
        User u = createSalesperson('gpdf2', 'gpdf2@example.com');
        NewsRun__c run = newRun(u, null);

        Boolean threw = false;
        try {
            NewsOfTheWeekController.generatePdf(run.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject when News Head is empty');
    }

    @isTest
    static void sendToRep_validatesAndReturnsEmail() {
        User u = createSalesperson('str1', 'rep1@example.com');
        NewsRun__c run = newRun(u, '<h2>Weekly Brief</h2><p>Signals this week.</p>');
        attachPdf(run.Id, 'News Run - 2026');

        Test.startTest();
        // Enqueues SendToRepQueueable (skipped in test) after synchronous validation.
        String email = NewsOfTheWeekController.sendToRep(run.Id);
        Test.stopTest();

        System.assertEquals('rep1@example.com', email, 'Returns the recipient email');
    }

    @isTest
    static void deliverToRep_sendsAndReturnsEmail() {
        User u = createSalesperson('dlv', 'dlv@example.com');
        NewsRun__c run = newRun(u, '<h2>Weekly Brief</h2><p>Signals.</p>');
        attachPdf(run.Id, 'News Run');

        Test.startTest();
        String email = NewsOfTheWeekController.deliverToRep(run.Id);
        Test.stopTest();

        System.assertEquals('dlv@example.com', email, 'deliverToRep returns the recipient email');
    }

    @isTest
    static void sendToRepQueueable_runsWithoutError() {
        User u = createSalesperson('q', 'q@example.com');
        NewsRun__c run = newRun(u, '<p>brief</p>');
        attachPdf(run.Id, 'News Run');

        Test.startTest();
        new SendToRepQueueable(run.Id).execute(null); // must not throw
        Test.stopTest();

        NewsOfTheWeek__c cfg = [
            SELECT Error_Log__c FROM NewsOfTheWeek__c WHERE Id = :run.News_Of_The_Week__c
        ];
        System.assert(String.isBlank(cfg.Error_Log__c), 'No error logged on a successful send');
    }

    @isTest
    static void sendToRep_throwsWhenNoPdf() {
        User u = createSalesperson('str2', 'rep2@example.com');
        NewsRun__c run = newRun(u, '<p>brief</p>');

        Boolean threw = false;
        try {
            NewsOfTheWeekController.sendToRep(run.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject when no PDF is attached');
    }

    private static NewsRun__c newRun(User u, String newsHead) {
        NewsOfTheWeek__c config = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert config;
        NewsRun__c run = new NewsRun__c(
            News_Of_The_Week__c = config.Id,
            Salesperson__c = u.Id,
            News_Head__c = newsHead,
            Run_Date__c = Date.today(),
            Status__c = 'Complete'
        );
        insert run;
        return run;
    }

    private static void attachPdf(Id recordId, String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            Origin = 'H'
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = recordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    private static User createSalesperson(String alias, String email) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias,
            Email = email,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Rep',
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
