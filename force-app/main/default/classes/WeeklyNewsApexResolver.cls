/**
 * Prompt Template Apex resolver for Weekly_News_Summary_PT.
 *
 * Given a NewsOfTheWeek__c parent record, queries every AccountNews__c child
 * and returns the concatenated news blocks. The prompt template references the
 * `prompt` output via a merge field (e.g. {!$Apex:WeeklyNewsApexResolver.prompt}).
 *
 * Bind this class as a Resource in Prompt Builder once after deploy — the UI
 * generates the exact merge expression for the body.
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
        description='Returns concatenated AccountNews__c.News__c blocks for a given NewsOfTheWeek__c, used by the Weekly News Summary prompt template.'
        callout=false
    )
    public static List<Response> aggregate(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.prompt = buildBlocks(req.news == null ? null : req.news.Id);
            out.add(r);
        }
        return out;
    }

    @TestVisible
    private static String buildBlocks(Id parentId) {
        if (parentId == null) {
            return '';
        }
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
            blocks.add('## ' + name + '\n' + body);
        }
        return String.join(blocks, '\n\n');
    }
}
