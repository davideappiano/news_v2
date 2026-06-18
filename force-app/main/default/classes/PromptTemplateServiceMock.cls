@isTest
public class PromptTemplateServiceMock extends PromptTemplateService {
    public List<String> calls = new List<String>();
    public Map<String, PromptTemplateService.PromptResult> resultByTemplate
        = new Map<String, PromptTemplateService.PromptResult>();
    public Boolean throwOnInvoke = false;

    public override PromptTemplateService.PromptResult invoke(String developerName, Map<String, Object> inputs) {
        calls.add(developerName);
        if (throwOnInvoke) {
            throw new CalloutException('Mocked failure');
        }
        if (resultByTemplate.containsKey(developerName)) {
            return resultByTemplate.get(developerName);
        }
        return new PromptTemplateService.PromptResult(
            '<p>Mock news for ' + developerName + '</p>',
            'https://example.com/source-1'
        );
    }
}
