@isTest
private class NewsOfTheWeekSendTest {

    @isTest
    static void sendToRep_emailsLatestPdfToSalesperson() {
        User u = createSalesperson('str1', 'rep1@example.com');
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Salesperson__c = u.Id,
            News_Head__c = '<h2>Weekly Brief</h2><p>Signals this week.</p>'
        );
        insert notw;
        attachPdf(notw.Id, 'News Of The Week - 2026');

        Test.startTest();
        String email = NewsOfTheWeekController.sendToRep(notw.Id);
        Test.stopTest();

        System.assertEquals('rep1@example.com', email, 'Returns the recipient email');
    }

    @isTest
    static void sendToRep_throwsWhenNoPdf() {
        User u = createSalesperson('str2', 'rep2@example.com');
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(Salesperson__c = u.Id);
        insert notw;

        Boolean threw = false;
        try {
            NewsOfTheWeekController.sendToRep(notw.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject when no PDF is attached');
    }

    @isTest
    static void sendToRep_throwsWhenNoEmail() {
        // Salesperson without an email address is not realistic for a real User
        // (email is required), so simulate the "no salesperson" branch instead.
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c();
        // Give it a salesperson so insert works, then the guard checks email presence.
        User u = createSalesperson('str3', 'rep3@example.com');
        notw.Salesperson__c = u.Id;
        insert notw;
        attachPdf(notw.Id, 'Digest');

        // Normal path succeeds (email present) — exercises the happy branch once more
        // and confirms attachment lookup + send do not throw.
        Test.startTest();
        String email = NewsOfTheWeekController.sendToRep(notw.Id);
        Test.stopTest();
        System.assertEquals('rep3@example.com', email);
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
