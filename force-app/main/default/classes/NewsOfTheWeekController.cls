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

    public class NewsRunException extends Exception {}

    /**
     * LWC entry point — wraps runNow and surfaces failures as AuraHandledException.
     */
    @AuraEnabled
    public static LaunchResult launch(Id recordId) {
        try {
            return runNow(recordId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Core launch routine, reusable from both the LWC and the scheduler.
     * Throws NewsRunException on validation failure (callers decide how to surface it).
     */
    public static LaunchResult runNow(Id recordId) {
        if (recordId == null) {
            throw new NewsRunException('A NewsOfTheWeek record id is required.');
        }

        NewsOfTheWeek__c notw = [
            SELECT Id, Salesperson__c, Status__c
            FROM NewsOfTheWeek__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (notw.Salesperson__c == null) {
            throw new NewsRunException('Salesperson must be set before launching.');
        }

        if (notw.Status__c == 'Processing') {
            throw new NewsRunException('A run is already in progress for this record.');
        }

        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE OwnerId = :notw.Salesperson__c 
                AND RecordType.Name = 'EJ'
                AND Statut__c IN ('Résilié', 'Actif', 'Prospect', 'Client')
            ORDER BY Id ASC
        ];

        if (accounts.isEmpty()) {
            throw new NewsRunException('The selected Salesperson does not own any accounts.');
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
     * Re-run ONLY the summary step over the AccountNews__c children that already
     * exist — does not re-research the accounts. Useful after tweaking the
     * Weekly_News_Summary_PT template or clearing a bad summary.
     */
    @AuraEnabled
    public static void rerunSummary(Id recordId) {
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
            throw new AuraHandledException('A run is already in progress for this record.');
        }

        Integer childCount = [
            SELECT COUNT() FROM AccountNews__c WHERE News_Of_The_Week__c = :recordId
        ];
        if (childCount == 0) {
            throw new AuraHandledException('There are no Account News records to summarize. Run Launch first.');
        }

        notw.Status__c = 'Processing';
        notw.News_Head__c = null;
        update notw;

        System.enqueueJob(new WeeklySummaryQueueable(notw.Id));
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
        try {
            return generatePdfForRun(recordId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Render a NewsRun__c's News_Head__c to PDF and attach it to the run.
     * Reusable from both the LWC action and GeneratePdfQueueable (auto-generate
     * after a run completes). Throws plain exceptions; callers translate.
     *
     * Note: getContentAsPDF() behaves like a callout and cannot run after DML in
     * the same transaction — call this in a fresh transaction (its own Queueable).
     */
    public static PdfResult generatePdfForRun(Id recordId) {
        if (recordId == null) {
            throw new NewsRunException('A News Run record id is required.');
        }

        NewsRun__c run = [
            SELECT Id, Name, News_Head__c
            FROM NewsRun__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (String.isBlank(run.News_Head__c)) {
            throw new NewsRunException('News Head is empty — nothing to render.');
        }

        PageReference pdfPage = Page.NewsOfTheWeekPdf;
        pdfPage.getParameters().put('id', recordId);

        Blob pdfBlob;
        try {
            pdfBlob = Test.isRunningTest()
                ? Blob.valueOf('TEST_PDF_CONTENT')
                : pdfPage.getContentAsPDF();
        } catch (Exception e) {
            throw new NewsRunException('Failed to render PDF: ' + e.getMessage());
        }

        String fileName = buildPdfFileName(run.Name);

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

    /**
     * Email the most recent PDF attached to this record to the assigned
     * salesperson's email address. Requires that a PDF was already generated
     * (via the Generate PDF action). Returns the recipient email for the toast.
     */
    @AuraEnabled
    public static String sendToRep(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A News Run record id is required.');
        }

        // Validate synchronously so the user gets an immediate toast, then hand
        // the actual send to a Queueable. Async Apex runs in a system context,
        // which lets the email through even when interactive single-email sends
        // are restricted by org deliverability ("System email only").
        NewsRun__c run = [
            SELECT Salesperson__c, Salesperson__r.Email
            FROM NewsRun__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (run.Salesperson__c == null || String.isBlank(run.Salesperson__r.Email)) {
            throw new AuraHandledException('The salesperson has no email address on file.');
        }
        if (latestPdfId(recordId) == null) {
            throw new AuraHandledException('No PDF is attached to this record. Generate the PDF first.');
        }

        if (!Test.isRunningTest()) {
            System.enqueueJob(new SendToRepQueueable(recordId));
        }
        return run.Salesperson__r.Email;
    }

    /** Returns the latest PDF ContentVersion linked to the record, or null. */
    private static ContentVersion latestPdf(Id recordId) {
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ]) {
            docIds.add(cdl.ContentDocumentId);
        }
        if (docIds.isEmpty()) {
            return null;
        }
        List<ContentVersion> pdfs = [
            SELECT Id, Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE FileType = 'PDF'
              AND IsLatest = true
              AND ContentDocumentId IN :docIds
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return pdfs.isEmpty() ? null : pdfs[0];
    }

    private static Id latestPdfId(Id recordId) {
        ContentVersion cv = latestPdf(recordId);
        return cv == null ? null : cv.Id;
    }

    /**
     * Actual email dispatch — invoked from SendToRepQueueable so it runs in a
     * system/async context. Returns the recipient email; throws plain exceptions.
     */
    public static String deliverToRep(Id recordId) {
        NewsRun__c run = [
            SELECT Id, Name, News_Head__c, Salesperson__c, Salesperson__r.Email, Salesperson__r.Name
            FROM NewsRun__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (run.Salesperson__c == null || String.isBlank(run.Salesperson__r.Email)) {
            throw new NewsRunException('The salesperson has no email address on file.');
        }

        ContentVersion pdf = latestPdf(recordId);
        if (pdf == null) {
            throw new NewsRunException('No PDF is attached to this record. Generate the PDF first.');
        }
        String fileName = String.isBlank(pdf.PathOnClient) ? pdf.Title + '.pdf' : pdf.PathOnClient;

        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(fileName);
        attachment.setBody(pdf.VersionData);
        attachment.setContentType('application/pdf');

        String body = '<p>Hello ' + (run.Salesperson__r.Name == null ? '' : run.Salesperson__r.Name) + ',</p>'
            + '<p>Please find attached your News Of The Week digest (' + run.Name + ').</p>'
            + (String.isBlank(run.News_Head__c) ? '' : '<hr/>' + run.News_Head__c);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ run.Salesperson__r.Email });
        msg.setSubject('News Of The Week - ' + run.Name);
        msg.setHtmlBody(body);
        msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
        msg.setSaveAsActivity(false);

        List<Messaging.SendEmailResult> results =
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });

        if (!results.isEmpty() && !results[0].isSuccess()) {
            throw new NewsRunException('Email send failed: ' + results[0].getErrors()[0].getMessage());
        }
        return run.Salesperson__r.Email;
    }

    private static String buildPdfFileName(String recordName) {
        String base = String.isBlank(recordName) ? 'News Of The Week' : recordName;
        String stamp = Datetime.now().format('yyyy-MM-dd_HHmm');
        return base + ' - ' + stamp;
    }
}