/**
 * Daily scheduler for automatic News Of The Week runs.
 *
 * Salesforce cron can't express "every N weeks", so this runs DAILY and launches
 * only the records that are actually due — each NewsOfTheWeek__c carries its own
 * cadence via Frequency_Days__c and Next_Run_Date__c. This supports any interval
 * (weekly, biweekly, monthly, …) with one scheduled job.
 *
 * Schedule it once (Setup can't do daily easily, so run this in anonymous Apex):
 *
 *   // 6:05 AM every day
 *   System.schedule('News Of The Week - Daily', '0 5 6 * * ?', new NewsOfTheWeekScheduler());
 *
 * or call the helper:
 *
 *   NewsOfTheWeekScheduler.scheduleDaily();
 */
public with sharing class NewsOfTheWeekScheduler implements Schedulable {

    /** Default cadence when Frequency_Days__c is blank or invalid. */
    @TestVisible
    private static final Integer DEFAULT_FREQUENCY_DAYS = 7;

    /** Convenience: schedule this job to run daily at 06:05. Returns the CronTrigger Id. */
    public static Id scheduleDaily() {
        return System.schedule(
            'News Of The Week - Daily',
            '0 5 6 * * ?',
            new NewsOfTheWeekScheduler()
        );
    }

    public void execute(SchedulableContext sc) {
        runDue();
    }

    /** Launch every schedule-active record whose Next Run Date has arrived. */
    @TestVisible
    private static void runDue() {
        Date today = Date.today();

        List<NewsOfTheWeek__c> due = [
            SELECT Id, Frequency_Days__c, Next_Run_Date__c, Status__c, Error_Log__c
            FROM NewsOfTheWeek__c
            WHERE Schedule_Active__c = true
              AND Next_Run_Date__c <= :today
              AND Status__c != 'Processing'
        ];

        List<NewsOfTheWeek__c> reschedules = new List<NewsOfTheWeek__c>();

        for (NewsOfTheWeek__c n : due) {
            Integer freq = (n.Frequency_Days__c == null || n.Frequency_Days__c <= 0)
                ? DEFAULT_FREQUENCY_DAYS
                : Integer.valueOf(n.Frequency_Days__c);

            try {
                NewsOfTheWeekController.runNow(n.Id);
                // Advance the schedule ONLY on a successful launch. Update via a
                // fresh, minimal SObject so we don't clobber the Status/counters
                // that runNow() just wrote on the record.
                reschedules.add(new NewsOfTheWeek__c(
                    Id = n.Id,
                    Next_Run_Date__c = today.addDays(freq)
                ));
            } catch (Exception e) {
                // Skip this record but keep going with the rest. Log for visibility;
                // Next_Run_Date__c is left as-is so it retries on the next daily run.
                reschedules.add(new NewsOfTheWeek__c(
                    Id = n.Id,
                    Error_Log__c = stamp(n.Error_Log__c,
                        'Scheduled launch skipped: ' + e.getMessage())
                ));
            }
        }

        if (!reschedules.isEmpty()) {
            update reschedules;
        }
    }

    private static String stamp(String existing, String entry) {
        String prior = String.isBlank(existing) ? '' : existing + '\n';
        return (prior + '[' + System.now().format() + '] ' + entry).left(32768);
    }
}
