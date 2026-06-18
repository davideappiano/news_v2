public with sharing virtual class PromptTemplateService {

    public class PromptResult {
        public String text;
        public String citations;
        public PromptResult(String text, String citations) {
            this.text = text;
            this.citations = citations;
        }
    }

    @TestVisible
    private static PromptTemplateService instance = new PromptTemplateService();

    public static PromptTemplateService getInstance() {
        return instance;
    }

    @TestVisible
    public static void setMock(PromptTemplateService mock) {
        instance = mock;
    }

    /**
     * Invoke a Prompt Template by developer name.
     *
     * @param developerName  Prompt Template developerName (e.g. 'Account_News_Research_PT')
     * @param inputs         Map keyed by the input *referenceName* declared on the
     *                       template (e.g. 'Input:account', 'Input:news').
     *                       For SObject inputs, you may pass the record itself —
     *                       the service rewraps it into the { id: <recordId> } shape
     *                       the platform expects for SOBJECT:// inputs.
     */
    public virtual PromptResult invoke(String developerName, Map<String, Object> inputs) {
        Map<String, ConnectApi.WrappedValue> templateInputs = new Map<String, ConnectApi.WrappedValue>();
        if (inputs != null) {
            for (String key : inputs.keySet()) {
                Object raw = inputs.get(key);
                ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
                wrapped.value = normalizeValue(raw);
                templateInputs.put(key, wrapped);
            }
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.inputParams = templateInputs;
        input.isPreview = false;
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(developerName, input);

        String text = '';
        if (response != null && response.generations != null && !response.generations.isEmpty()) {
            text = response.generations[0].text;
        }
        return new PromptResult(text, '');
    }

    /**
     * SObject inputs to Prompt Templates must be passed as { id: '<recordId>' };
     * passing the raw SObject is rejected at runtime with "Invalid input value: [Account (...)]".
     */
    @TestVisible
    private static Object normalizeValue(Object raw) {
        if (raw instanceof SObject) {
            SObject so = (SObject) raw;
            Id recId = (Id) so.get('Id');
            return new Map<String, String>{ 'id' => recId == null ? '' : (String) recId };
        }
        return raw;
    }
}
