/*
 * Registers (or re-registers) the daily News Of The Week scheduler.
 *
 * Equivalent to Setup → Apex Classes → Schedule Apex, but scriptable/repeatable.
 * Run with:
 *   sf apex run -f scripts/apex/scheduleNewsOfTheWeek.apex --target-org <alias>
 *
 * Idempotent: if a job with this name already exists it is aborted first, so
 * re-running never throws "That class is already scheduled for execution".
 */
String jobName = 'News Of The Week - Daily';
String cron = '0 5 6 * * ?'; // 06:05 every day (seconds minutes hours day month day-of-week)

// Abort any existing job with the same name.
for (CronTrigger ct : [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
]) {
    System.abortJob(ct.Id);
    System.debug('Aborted existing job ' + ct.Id);
}

Id jobId = System.schedule(jobName, cron, new NewsOfTheWeekScheduler());
System.debug('Scheduled ' + jobName + ' -> ' + jobId);
