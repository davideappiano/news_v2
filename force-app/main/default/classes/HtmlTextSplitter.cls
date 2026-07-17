/**
 * Invocable action that strips HTML tags from an input string and splits the
 * resulting plain text into chunks of at most CHUNK_SIZE characters.
 *
 * Because @InvocableMethod signatures must be List-based, each request carries a
 * single input string and each response carries the list of chunks produced for
 * that string. Requests and responses are index-aligned.
 */
public with sharing class HtmlTextSplitter {
    @TestVisible
    private static final Integer DEFAULT_CHUNK_SIZE = 500;

    public class Request {
        @InvocableVariable(label='Input Text' description='HTML or plain text to clean and split' required=true)
        public String inputText;

        @InvocableVariable(label='Chunk Size' description='Maximum characters per chunk (defaults to 500 when blank or non-positive)')
        public Integer chunkSize;
    }

    public class Response {
        @InvocableVariable(label='Text Chunks' description='Plain-text chunks of at most 500 characters')
        public List<String> chunks;

        public Response() {
            this.chunks = new List<String>();
        }
    }

    @InvocableMethod(
        label='Strip HTML and Split Text'
        description='Removes HTML tags from a string and splits it into a list of chunks of at most 500 characters.'
        category='Text'
    )
    public static List<Response> stripAndSplit(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(splitText(req?.inputText, req?.chunkSize));
        }
        return responses;
    }

    private static Response splitText(String inputText, Integer requestedChunkSize) {
        Response response = new Response();
        if (String.isBlank(inputText)) {
            return response;
        }

        String plainText = inputText.stripHtmlTags();
        if (String.isBlank(plainText)) {
            return response;
        }

        Integer chunkSize = (requestedChunkSize != null && requestedChunkSize > 0)
            ? requestedChunkSize
            : DEFAULT_CHUNK_SIZE;

        Integer length = plainText.length();
        for (Integer start = 0; start < length; start += chunkSize) {
            Integer ends = Math.min(start + chunkSize, length);
            response.chunks.add(plainText.substring(start, ends));
        }
        return response;
    }
}
