public with sharing class AccountOpportunitiesController {

    /**
     * Returns a list of all Accounts for the picklist combobox.
     * @return List of Account records (Id + Name)
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccounts() {
        return [
            SELECT Id, Name
            FROM Account
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    /**
     * Returns the total Amount of all Opportunities for a given Account.
     * @param accountId - the Id of the selected Account
     * @return Decimal total amount (0 if no opportunities)
     */
    @AuraEnabled(cacheable=true)
    public static Decimal getOpportunityTotal(Id accountId) {
        if (accountId == null) {
            return 0;
        }
        AggregateResult[] results = [
            SELECT SUM(Amount) totalAmount
            FROM Opportunity
            WHERE AccountId = :accountId
        ];
        if (results != null && !results.isEmpty()) {
            Decimal total = (Decimal) results[0].get('totalAmount');
            return total != null ? total : 0;
        }
        return 0;
    }
}