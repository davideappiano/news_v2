@IsTest
private class HtmlTextSplitterTest {
    @IsTest
    static void stripsHtmlAndReturnsSingleChunk() {
        HtmlTextSplitter.Request req = new HtmlTextSplitter.Request();
        req.inputText = '<p>Hello <b>World</b></p>';

        Test.startTest();
        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(
            new List<HtmlTextSplitter.Request>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One response expected per request');
        Assert.areEqual(1, results[0].chunks.size(), 'Short text fits in one chunk');
        Assert.areEqual('Hello World', results[0].chunks[0], 'HTML tags should be stripped');
    }

    @IsTest
    static void splitsLongTextIntoMaxLengthChunks() {
        // 1250 chars of tag-free content -> 500 + 500 + 250
        String longText = 'a'.repeat(1250);
        HtmlTextSplitter.Request req = new HtmlTextSplitter.Request();
        req.inputText = longText;

        Test.startTest();
        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(
            new List<HtmlTextSplitter.Request>{ req }
        );
        Test.stopTest();

        List<String> chunks = results[0].chunks;
        Assert.areEqual(3, chunks.size(), 'Expected three chunks');
        Assert.areEqual(500, chunks[0].length(), 'First chunk should be full');
        Assert.areEqual(500, chunks[1].length(), 'Second chunk should be full');
        Assert.areEqual(250, chunks[2].length(), 'Last chunk holds the remainder');
        Assert.areEqual(longText, String.join(chunks, ''), 'Chunks should reconstruct the source');
    }

    @IsTest
    static void respectsRequestedChunkSize() {
        HtmlTextSplitter.Request req = new HtmlTextSplitter.Request();
        req.inputText = 'c'.repeat(250);
        req.chunkSize = 100;

        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(
            new List<HtmlTextSplitter.Request>{ req }
        );

        List<String> chunks = results[0].chunks;
        Assert.areEqual(3, chunks.size(), 'Expected 100 + 100 + 50');
        Assert.areEqual(100, chunks[0].length(), 'Chunk respects requested size');
        Assert.areEqual(50, chunks[2].length(), 'Last chunk holds the remainder');
    }

    @IsTest
    static void fallsBackToDefaultWhenChunkSizeInvalid() {
        HtmlTextSplitter.Request nullSize = new HtmlTextSplitter.Request();
        nullSize.inputText = 'd'.repeat(600);
        HtmlTextSplitter.Request zeroSize = new HtmlTextSplitter.Request();
        zeroSize.inputText = 'e'.repeat(600);
        zeroSize.chunkSize = 0;

        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(
            new List<HtmlTextSplitter.Request>{ nullSize, zeroSize }
        );

        Assert.areEqual(500, results[0].chunks[0].length(), 'Null size falls back to default 500');
        Assert.areEqual(500, results[1].chunks[0].length(), 'Non-positive size falls back to default 500');
    }

    @IsTest
    static void handlesExactMultipleOfChunkSize() {
        HtmlTextSplitter.Request req = new HtmlTextSplitter.Request();
        req.inputText = 'b'.repeat(1000);

        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(
            new List<HtmlTextSplitter.Request>{ req }
        );

        Assert.areEqual(2, results[0].chunks.size(), 'Exactly two full chunks, no empty trailing chunk');
    }

    @IsTest
    static void returnsEmptyForBlankOrNullInput() {
        HtmlTextSplitter.Request nullReq = new HtmlTextSplitter.Request();
        HtmlTextSplitter.Request blankReq = new HtmlTextSplitter.Request();
        blankReq.inputText = '   ';

        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(
            new List<HtmlTextSplitter.Request>{ nullReq, blankReq }
        );

        Assert.areEqual(2, results.size(), 'Response per request preserved');
        Assert.isTrue(results[0].chunks.isEmpty(), 'Null input yields no chunks');
        Assert.isTrue(results[1].chunks.isEmpty(), 'Blank input yields no chunks');
    }

    @IsTest
    static void processesBulkRequests() {
        List<HtmlTextSplitter.Request> requests = new List<HtmlTextSplitter.Request>();
        for (Integer i = 0; i < 200; i++) {
            HtmlTextSplitter.Request req = new HtmlTextSplitter.Request();
            req.inputText = '<span>Row ' + i + '</span>';
            requests.add(req);
        }

        Test.startTest();
        List<HtmlTextSplitter.Response> results = HtmlTextSplitter.stripAndSplit(requests);
        Test.stopTest();

        Assert.areEqual(200, results.size(), 'One response per request');
        Assert.areEqual('Row 0', results[0].chunks[0], 'First row cleaned correctly');
        Assert.areEqual('Row 199', results[199].chunks[0], 'Last row cleaned correctly');
    }
}
