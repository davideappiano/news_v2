@isTest
private class NewsOfTheWeekSchedulerTest {

    @isTest
    static void runDue_skipsAndLogsWhenLaunchFails() {
        // Schedule-active, due, but no Salesperson → runNow throws → logged, not rescheduled.
        NewsOfTheWeek__c notw = new NewsOfTheWeek__c(
            Schedule_Active__c = true,
            Frequency_Days__c = 14,
            Next_Run_Date__c = Date.today().addDays(-1),
            Status__c = 'Draft'
        );
        insert notw;

        Test.startTest();
        new NewsOfTheWeekScheduler().execute(null);
        Test.stopTest();

        NewsOfTheWeek__c after = [
            SELECT Error_Log__c, Next_Run_Date__c FROM NewsOfTheWeek__c WHERE Id = :notw.Id
        ];
        System.assert(after.Error_Log__c != null && after.Error_Log__c.contains('Scheduled launch skipped'),
            'Failure logged');
        System.assertEquals(Date.today().addDays(-1), after.Next_Run_Date__c,
            'Next Run Date left unchanged so it retries next day');
    }

    @isTest
    static void runDue_ignoresInactiveAndFutureRecords() {
        NewsOfTheWeek__c inactive = new NewsOfTheWeek__c(
            Schedule_Active__c = false,
            Next_Run_Date__c = Date.today().addDays(-1),
            Status__c = 'Draft'
        );
        NewsOfTheWeek__c future = new NewsOfTheWeek__c(
            Schedule_Active__c = true,
            Next_Run_Date__c = Date.today().addDays(5),
            Status__c = 'Draft'
        );
        insert new List<NewsOfTheWeek__c>{ inactive, future };

        Test.startTest();
        new NewsOfTheWeekScheduler().execute(null);
        Test.stopTest();

        for (NewsOfTheWeek__c n : [SELECT Error_Log__c FROM NewsOfTheWeek__c]) {
            System.assert(String.isBlank(n.Error_Log__c), 'Neither inactive nor future record was touched');
        }
    }

    @isTest
    static void scheduleDaily_registersCronJob() {
        Test.startTest();
        Id jobId = NewsOfTheWeekScheduler.scheduleDaily();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'A scheduled job id is returned');
        CronTrigger ct = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 5 6 * * ?', ct.CronExpression, 'Daily 6:05 cron registered');
    }
}
