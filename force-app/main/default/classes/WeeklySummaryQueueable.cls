public with sharing class WeeklySummaryQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final String TEMPLATE_DEVELOPER_NAME = 'Weekly_News_Summary_PT';

    private final Id newsOfTheWeekId;

    public WeeklySummaryQueueable(Id newsOfTheWeekId) {
        this.newsOfTheWeekId = newsOfTheWeekId;
    }

    public void execute(QueueableContext ctx) {
        NewsOfTheWeek__c parent = [
            SELECT Id, Salesperson__c, Run_Date__c, Status__c, Error_Log__c,
                   Total_Accounts__c, Processed_Accounts__c, Notify_Rep_By_Email__c
            FROM NewsOfTheWeek__c
            WHERE Id = :newsOfTheWeekId
            LIMIT 1
        ];

        Integer childCount = [
            SELECT COUNT()
            FROM AccountNews__c
            WHERE News_Of_The_Week__c = :newsOfTheWeekId
        ];

        if (childCount == 0) {
            parent.Status__c = 'Failed';
            parent.Error_Log__c = appendErr(parent.Error_Log__c,
                'No AccountNews children were produced; nothing to summarize.');
            update parent;
            return;
        }

        try {
            // The prompt template's Apex resolver (WeeklyNewsApexResolver) loads
            // every AccountNews__c attached to this parent record at template
            // evaluation time, so we only need to hand the parent SObject in.
            // Key matches the prompt template input's referenceName (Input:news),
            // which is what ConnectApi.EinsteinLLM matches on at runtime. The
            // template's WeeklyNewsApexResolver data provider then loads every
            // AccountNews__c child for this parent at evaluation time.
            Map<String, Object> inputs = new Map<String, Object>{
                'Input:news' => parent
            };

            PromptTemplateService.PromptResult result =
                PromptTemplateService.getInstance().invoke(TEMPLATE_DEVELOPER_NAME, inputs);

            parent.News_Head__c = String.isBlank(result.text)
                ? '<p><em>No summary produced.</em></p>'
                : result.text;
            parent.Status__c = 'Complete';
            update parent;

            archiveRun(parent);
        } catch (Exception e) {
            parent.Status__c = 'Failed';
            parent.Error_Log__c = appendErr(parent.Error_Log__c,
                'Summary step failed: ' + e.getTypeName() + ' - ' + e.getMessage());
            update parent;
        }
    }

    /**
     * Snapshot a successfully completed run into a NewsRun__c archive record so
     * past newsletters are preserved when the next run overwrites News_Head__c.
     * Wrapped so an archive failure never flips a genuinely-complete run to Failed.
     */
    private void archiveRun(NewsOfTheWeek__c parent) {
        try {
            NewsRun__c run = new NewsRun__c(
                News_Of_The_Week__c = parent.Id,
                Salesperson__c = parent.Salesperson__c,
                News_Head__c = parent.News_Head__c,
                Run_Date__c = parent.Run_Date__c,
                Status__c = 'Complete',
                Total_Accounts__c = parent.Total_Accounts__c,
                Processed_Accounts__c = parent.Processed_Accounts__c
            );
            insert run;

            // Move the per-account news off the live config and onto the archived
            // run, so the config's workspace is clear for the next run while the
            // history stays browsable under the NewsRun.
            List<AccountNews__c> children = [
                SELECT Id
                FROM AccountNews__c
                WHERE News_Of_The_Week__c = :parent.Id
            ];
            for (AccountNews__c c : children) {
                c.News_Run__c = run.Id;
                c.News_Of_The_Week__c = null;
            }
            if (!children.isEmpty()) {
                update children;
            }

            // Finalize the freshly archived run in its own transaction (the DML
            // above rules out getContentAsPDF here): generate the PDF, then email
            // it to the rep.
            if (!Test.isRunningTest()) {
                System.enqueueJob(new NewsRunDeliveryQueueable(run.Id, true, parent.Notify_Rep_By_Email__c));
            }
        } catch (Exception e) {
            try {
                NewsOfTheWeek__c log = new NewsOfTheWeek__c(
                    Id = parent.Id,
                    Error_Log__c = appendErr(parent.Error_Log__c,
                        'Run completed but archive (NewsRun) failed: ' + e.getMessage())
                );
                update log;
            } catch (Exception ignored) {
                // never let archive logging break a completed run
            }
        }
    }

    private String appendErr(String existing, String entry) {
        String prior = existing == null ? '' : existing + '\n';
        return (prior + '[' + System.now().format() + '] ' + entry).left(32768);
    }
}
