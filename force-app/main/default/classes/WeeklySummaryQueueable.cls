/**
 * Map-reduce summarizer. A single prompt over all AccountNews__c children blows
 * past the Einstein Trust Layer token cap (worse with PII masking on), so we:
 *
 *   MAP    — process the children in chunks of CHUNK_SIZE. Each chunk is
 *            summarized (Weekly_News_Chunk_PT) into a compact partial, appended
 *            to NewsOfTheWeek__c.Partial_Summaries__c. Chunks are chained one per
 *            Queueable execution so each callout stays small and isolated.
 *   REDUCE — once every chunk is mapped, a final pass (Weekly_News_Summary_PT,
 *            whose resolver now returns the accumulated partials) produces the
 *            executive brief in News_Head__c.
 *
 * DML-vs-callout ordering: within an execution we always do the callout FIRST,
 * then DML (append partial / write result). The REDUCE runs as its own chained
 * execution so it starts with no pending DML before its callout.
 *
 * Note: chunk paging uses SOQL OFFSET, capped at 2000 rows. Portfolios beyond
 * 2000 accounts would need keyset pagination instead.
 */
public with sharing class WeeklySummaryQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final String CHUNK_TEMPLATE = 'Weekly_News_Chunk_PT';
    @TestVisible
    private static final String REDUCE_TEMPLATE = 'Weekly_News_Summary_PT';

    /** Account News records summarized per MAP execution. */
    @TestVisible
    private static Integer CHUNK_SIZE = 300;

    private final Id newsOfTheWeekId;
    private final Integer chunkIndex;
    private final Boolean reducePhase;

    /** Public entry point — starts the MAP phase at chunk 0. */
    public WeeklySummaryQueueable(Id newsOfTheWeekId) {
        this(newsOfTheWeekId, 0, false);
    }

    @TestVisible
    private WeeklySummaryQueueable(Id newsOfTheWeekId, Integer chunkIndex, Boolean reducePhase) {
        this.newsOfTheWeekId = newsOfTheWeekId;
        this.chunkIndex = chunkIndex;
        this.reducePhase = reducePhase;
    }

    public void execute(QueueableContext ctx) {
        if (reducePhase) {
            doReduce();
        } else {
            doMap();
        }
    }

    // ---- MAP -------------------------------------------------------------

    private void doMap() {
        Integer total = [
            SELECT COUNT()
            FROM AccountNews__c
            WHERE News_Of_The_Week__c = :newsOfTheWeekId
        ];

        if (total == 0) {
            NewsOfTheWeek__c parent = new NewsOfTheWeek__c(Id = newsOfTheWeekId);
            parent.Status__c = 'Failed';
            parent.Error_Log__c = stamp('No AccountNews children were produced; nothing to summarize.');
            update parent;
            return;
        }

        List<AccountNews__c> chunk = [
            SELECT Account__r.Name, News__c
            FROM AccountNews__c
            WHERE News_Of_The_Week__c = :newsOfTheWeekId
            ORDER BY Account__r.Name ASC, Id ASC
            LIMIT :CHUNK_SIZE
            OFFSET :(chunkIndex * CHUNK_SIZE)
        ];

        String chunkText = buildChunkText(chunk);

        try {
            if (String.isNotBlank(chunkText)) {
                // CALLOUT first (before any DML this transaction).
                PromptTemplateService.PromptResult result =
                    PromptTemplateService.getInstance().invoke(
                        CHUNK_TEMPLATE,
                        new Map<String, Object>{ 'Input:chunk' => chunkText }
                    );
                if (String.isNotBlank(result.text)
                        && !result.text.trim().equalsIgnoreCase('NO_MATERIAL_SIGNALS')) {
                    appendPartial(result.text);
                }
            }
        } catch (Exception e) {
            appendError('Chunk ' + chunkIndex + ' failed: ' + e.getTypeName() + ' - ' + e.getMessage());
        }

        Integer nextOffset = (chunkIndex + 1) * CHUNK_SIZE;
        if (nextOffset < total) {
            // More chunks — continue MAP.
            if (!Test.isRunningTest()) {
                System.enqueueJob(new WeeklySummaryQueueable(newsOfTheWeekId, chunkIndex + 1, false));
            }
        } else {
            // All chunks mapped — hand off to REDUCE in a fresh transaction.
            if (!Test.isRunningTest()) {
                System.enqueueJob(new WeeklySummaryQueueable(newsOfTheWeekId, 0, true));
            }
        }
    }

    /** Build the chunk text, filtering "No news" blocks (Solution 1). */
    @TestVisible
    private String buildChunkText(List<AccountNews__c> chunk) {
        List<String> blocks = new List<String>();
        for (AccountNews__c c : chunk) {
            String body = c.News__c == null ? '' : c.News__c;
            if (body.contains('No news')) {
                continue;
            }
            String name = (c.Account__r != null && c.Account__r.Name != null)
                ? c.Account__r.Name
                : 'Unknown account';
            blocks.add('## ' + name + '\n' + body);
        }
        return String.join(blocks, '\n\n');
    }

    private void appendPartial(String partial) {
        NewsOfTheWeek__c parent = [
            SELECT Partial_Summaries__c
            FROM NewsOfTheWeek__c
            WHERE Id = :newsOfTheWeekId
            FOR UPDATE
        ];
        String prior = String.isBlank(parent.Partial_Summaries__c) ? '' : parent.Partial_Summaries__c + '\n\n';
        parent.Partial_Summaries__c = (prior + partial.trim()).left(131072);
        update parent;
    }

    // ---- REDUCE ----------------------------------------------------------

    private void doReduce() {
        NewsOfTheWeek__c parent = [
            SELECT Id, Partial_Summaries__c, Status__c, Error_Log__c
            FROM NewsOfTheWeek__c
            WHERE Id = :newsOfTheWeekId
            LIMIT 1
        ];

        if (String.isBlank(parent.Partial_Summaries__c)) {
            parent.News_Head__c = '<p><em>No commercially relevant news was found across the researched accounts this period.</em></p>';
            parent.Status__c = 'Complete';
            update parent;
            return;
        }

        try {
            // Reuse the existing reduce template; its resolver returns the
            // (small) accumulated partials rather than all account news.
            PromptTemplateService.PromptResult result =
                PromptTemplateService.getInstance().invoke(
                    REDUCE_TEMPLATE,
                    new Map<String, Object>{ 'Input:news' => parent }
                );

            parent.News_Head__c = String.isBlank(result.text)
                ? '<p><em>No summary produced.</em></p>'
                : result.text;
            parent.Status__c = 'Complete';
            update parent;
        } catch (Exception e) {
            parent.Status__c = 'Failed';
            parent.Error_Log__c = stamp('Reduce step failed: ' + e.getTypeName() + ' - ' + e.getMessage(), parent.Error_Log__c);
            update parent;
        }
    }

    // ---- helpers ---------------------------------------------------------

    private void appendError(String entry) {
        try {
            NewsOfTheWeek__c parent = [
                SELECT Id, Error_Log__c FROM NewsOfTheWeek__c WHERE Id = :newsOfTheWeekId LIMIT 1
            ];
            parent.Error_Log__c = stamp(entry, parent.Error_Log__c);
            update parent;
        } catch (Exception ignored) {
            // never let logging break the chain
        }
    }

    private String stamp(String entry) {
        return stamp(entry, null);
    }

    private String stamp(String entry, String existing) {
        String prior = String.isBlank(existing) ? '' : existing + '\n';
        return (prior + '[' + System.now().format() + '] ' + entry).left(32768);
    }
}
