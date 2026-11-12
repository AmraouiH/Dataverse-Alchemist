/**
  * Credit limit alert on the account.
 * Web resource : rhz_/js/account.information.js
  * Shows a warning on the Information form when Credit Limit exceeds the threshold (message in the CRM language, French).
  * Parameters provided by the form: executionContext (passExecutionContext set to true).
 */
var Alchemist = window.Alchemist || {};
Alchemist.Account = Alchemist.Account || {};
Alchemist.Account.Information = (function () {
    "use strict";

    var CREDIT_LIMIT_THRESHOLD = 100000;
    var CREDIT_LIMIT_NOTIFICATION_ID = "rhz_account_creditlimit";
    var CREDIT_LIMIT_MESSAGE = "La limite de crédit dépasse 100 000.";

    function getAttributeValue(formContext, name) {
        var attribute = formContext.getAttribute(name);
        return attribute ? attribute.getValue() : null;
    }

    /* Shows the warning above the threshold, removes it below */
    function checkCreditLimit(formContext) {
        var creditLimit = getAttributeValue(formContext, "creditlimit");
        if (creditLimit > CREDIT_LIMIT_THRESHOLD) {
            formContext.ui.setFormNotification(CREDIT_LIMIT_MESSAGE, "WARNING", CREDIT_LIMIT_NOTIFICATION_ID);
        } else {
            formContext.ui.clearFormNotification(CREDIT_LIMIT_NOTIFICATION_ID);
        }
    }

    /* Form handlers */

    function onLoad(executionContext) {
        checkCreditLimit(executionContext.getFormContext());
    }

    function onCreditLimitChange(executionContext) {
        checkCreditLimit(executionContext.getFormContext());
    }

    return {
        onLoad: onLoad,
        onCreditLimitChange: onCreditLimitChange
    };
})();
