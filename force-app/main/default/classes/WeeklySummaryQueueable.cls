public with sharing class WeeklySummaryQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final String TEMPLATE_DEVELOPER_NAME = 'Weekly_News_Summary_PT';

    private final Id newsOfTheWeekId;

    public WeeklySummaryQueueable(Id newsOfTheWeekId) {
        this.newsOfTheWeekId = newsOfTheWeekId;
    }

    public void execute(QueueableContext ctx) {
        NewsOfTheWeek__c parent = [
            SELECT Id, Salesperson__c, Run_Date__c, Status__c, Error_Log__c
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
        } catch (Exception e) {
            parent.Status__c = 'Failed';
            parent.Error_Log__c = appendErr(parent.Error_Log__c,
                'Summary step failed: ' + e.getTypeName() + ' - ' + e.getMessage());
            update parent;
        }
    }

    private String appendErr(String existing, String entry) {
        String prior = existing == null ? '' : existing + '\n';
        return (prior + '[' + System.now().format() + '] ' + entry).left(32768);
    }
}
