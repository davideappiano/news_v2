public with sharing class NewsOfTheWeekController {

    public class LaunchResult {
        @AuraEnabled public Integer accountCount;
        @AuraEnabled public Integer streamCount;
        @AuraEnabled public String message;
        public LaunchResult(Integer accountCount, Integer streamCount, String message) {
            this.accountCount = accountCount;
            this.streamCount = streamCount;
            this.message = message;
        }
    }

    @AuraEnabled
    public static LaunchResult launch(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A NewsOfTheWeek record id is required.');
        }

        NewsOfTheWeek__c notw = [
            SELECT Id, Salesperson__c, Status__c
            FROM NewsOfTheWeek__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (notw.Salesperson__c == null) {
            throw new AuraHandledException('Salesperson must be set before launching.');
        }

        if (notw.Status__c == 'Processing') {
            throw new AuraHandledException('A run is already in progress for this record.');
        }

        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE OwnerId = :notw.Salesperson__c
            ORDER BY Id ASC
        ];

        if (accounts.isEmpty()) {
            throw new AuraHandledException('The selected Salesperson does not own any accounts.');
        }

        // Round-robin distribute account ids across STREAM_COUNT parallel streams.
        // Stream i owns accounts at indexes i, i+streamCount, i+2*streamCount, …
        Integer streamCount = Math.min(accounts.size(), AccountResearchBatch.STREAM_COUNT);
        Map<Integer, List<Id>> streamIds = new Map<Integer, List<Id>>();
        for (Integer i = 0; i < streamCount; i++) {
            streamIds.put(i, new List<Id>());
        }
        for (Integer i = 0; i < accounts.size(); i++) {
            streamIds.get(Math.mod(i, streamCount)).add(accounts[i].Id);
        }

        // Wipe prior children so the new run starts fresh.
        delete [SELECT Id FROM AccountNews__c WHERE News_Of_The_Week__c = :notw.Id];

        notw.Status__c = 'Processing';
        notw.Run_Date__c = Date.today();
        notw.Error_Log__c = null;
        notw.News_Head__c = null;
        notw.Total_Accounts__c = accounts.size();
        notw.Processed_Accounts__c = 0;
        notw.Active_Streams__c = streamCount;
        update notw;

        // Fire one batch job per stream — up to 5 in this transaction (the platform's
        // executeBatch-per-transaction cap). Each stream's first page has pageIndex=0;
        // its finish() will chain pageIndex+1 until the stream's id list is exhausted.
        for (Integer i = 0; i < streamCount; i++) {
            Database.executeBatch(
                new AccountResearchBatch(
                    notw.Id,
                    streamIds.get(i),
                    0,
                    AccountResearchBatch.DEFAULT_PAGE_SIZE
                ),
                AccountResearchBatch.EXECUTE_BATCH_SIZE
            );
        }

        return new LaunchResult(
            accounts.size(),
            streamCount,
            'Background research started across ' + streamCount + ' parallel stream(s).'
        );
    }

    /**
     * Wipe a NewsOfTheWeek__c run back to a clean Draft state.
     */
    @AuraEnabled
    public static Integer reset(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A NewsOfTheWeek record id is required.');
        }

        NewsOfTheWeek__c notw = [
            SELECT Id, Status__c
            FROM NewsOfTheWeek__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (notw.Status__c == 'Processing') {
            throw new AuraHandledException(
                'Cannot reset while a run is Processing. Wait for it to finish or fail first.'
            );
        }

        List<AccountNews__c> children = [
            SELECT Id FROM AccountNews__c WHERE News_Of_The_Week__c = :recordId
        ];
        Integer deleted = children.size();
        if (deleted > 0) {
            delete children;
        }

        notw.News_Head__c = null;
        notw.Error_Log__c = null;
        notw.Run_Date__c = null;
        notw.Status__c = 'Draft';
        notw.Total_Accounts__c = null;
        notw.Processed_Accounts__c = null;
        notw.Active_Streams__c = null;
        update notw;

        return deleted;
    }

    public class PdfResult {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String fileName;
        public PdfResult(Id contentDocumentId, String fileName) {
            this.contentDocumentId = contentDocumentId;
            this.fileName = fileName;
        }
    }

    /**
     * Render News_Head__c as a PDF via the NewsOfTheWeekPdf Visualforce page
     * and attach it to the record as a Salesforce File.
     */
    @AuraEnabled
    public static PdfResult generatePdf(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A NewsOfTheWeek record id is required.');
        }

        NewsOfTheWeek__c notw = [
            SELECT Id, Name, News_Head__c
            FROM NewsOfTheWeek__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (String.isBlank(notw.News_Head__c)) {
            throw new AuraHandledException('News Head is empty — nothing to render.');
        }

        PageReference pdfPage = Page.NewsOfTheWeekPdf;
        pdfPage.getParameters().put('id', recordId);

        Blob pdfBlob;
        try {
            pdfBlob = Test.isRunningTest()
                ? Blob.valueOf('TEST_PDF_CONTENT')
                : pdfPage.getContentAsPDF();
        } catch (Exception e) {
            throw new AuraHandledException('Failed to render PDF: ' + e.getMessage());
        }

        String fileName = buildPdfFileName(notw);

        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName + '.pdf',
            VersionData = pdfBlob,
            Origin = 'H'
        );
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ].ContentDocumentId;

        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = recordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert link;

        return new PdfResult(contentDocumentId, fileName + '.pdf');
    }

    private static String buildPdfFileName(NewsOfTheWeek__c notw) {
        String base = String.isBlank(notw.Name) ? 'News Of The Week' : notw.Name;
        String stamp = Datetime.now().format('yyyy-MM-dd_HHmm');
        return base + ' - ' + stamp;
    }
}
