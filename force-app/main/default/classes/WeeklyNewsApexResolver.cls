/**
 * Prompt Template Apex resolver for Weekly_News_Summary_PT (the REDUCE prompt).
 *
 * The summary runs as a map-reduce (see WeeklySummaryQueueable):
 *   MAP    — WeeklySummaryQueueable summarizes chunks of ~300 AccountNews__c
 *            into partial summaries, appended to NewsOfTheWeek__c.Partial_Summaries__c.
 *   REDUCE — Weekly_News_Summary_PT summarizes those partials into News_Head__c.
 *
 * So this resolver returns the (small) accumulated partial summaries when they
 * exist. It falls back to the raw per-account blocks only when no partials were
 * produced (e.g. a tiny portfolio processed in a single pass) — with "No news"
 * blocks filtered out (Solution 1).
 */
public with sharing class WeeklyNewsApexResolver {

    public class Request {
        @InvocableVariable(required=true)
        public NewsOfTheWeek__c news;
    }

    public class Response {
        @InvocableVariable
        public String prompt;
    }

    @InvocableMethod(
        label='Aggregate Account News for Week'
        description='Returns the accumulated partial summaries (or filtered per-account blocks) for a NewsOfTheWeek__c, used by the Weekly News Summary reduce prompt.'
        callout=false
    )
    public static List<Response> aggregate(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.prompt = buildPrompt(req.news == null ? null : req.news.Id);
            out.add(r);
        }
        return out;
    }

    @TestVisible
    private static String buildPrompt(Id parentId) {
        if (parentId == null) {
            return '';
        }

        // REDUCE input: the accumulated partial summaries, if any.
        NewsOfTheWeek__c parent = [
            SELECT Partial_Summaries__c
            FROM NewsOfTheWeek__c
            WHERE Id = :parentId
            LIMIT 1
        ];
        if (String.isNotBlank(parent.Partial_Summaries__c)) {
            return parent.Partial_Summaries__c;
        }

        // Fallback: build directly from per-account blocks (single-pass, small portfolios).
        return buildBlocks(parentId);
    }

    @TestVisible
    private static String buildBlocks(Id parentId) {
        List<AccountNews__c> children = [
            SELECT Account__r.Name, News__c
            FROM AccountNews__c
            WHERE News_Of_The_Week__c = :parentId
            ORDER BY Account__r.Name ASC
        ];
        if (children.isEmpty()) {
            return 'No per-account research blocks were produced for this run.';
        }
        List<String> blocks = new List<String>();
        for (AccountNews__c c : children) {
            String name = (c.Account__r != null && c.Account__r.Name != null)
                ? c.Account__r.Name
                : 'Unknown account';
            String body = c.News__c == null ? '' : c.News__c;
            // Solution 1: skip accounts with no material news.
            if (!body.contains('No news')) {
                blocks.add('## ' + name + '\n' + body);
            }
        }
        if (blocks.isEmpty()) {
            return 'No commercially relevant news was found across the researched accounts this period.';
        }
        return String.join(blocks, '\n\n');
    }
}
