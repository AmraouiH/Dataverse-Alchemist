/**
  * Service contract date consistency (CRM-414).
 * Web resource : rhz_/js/rhz_contratservice.information.js
  * Shows an error on the end date when it is before the start date, and blocks saving (message in the CRM language, French).
  * Parameters provided by the form: executionContext (passExecutionContext set to true).
 */
var Alchemist = window.Alchemist || {};
Alchemist.ContratService = Alchemist.ContratService || {};
Alchemist.ContratService.Information = (function () {
    "use strict";

    var START_DATE = "rhz_datedebut";
    var END_DATE = "rhz_datefin";
    var NOTIFICATION_ID = "rhz_contratservice_dates";
    var MESSAGE = "La date de fin doit être postérieure ou égale à la date de début.";

    function getAttributeValue(formContext, name) {
        var attribute = formContext.getAttribute(name);
        return attribute ? attribute.getValue() : null;
    }

    /* Inconsistent dates: both are set and the end is before the start (day only) */
    function areDatesInconsistent(startDate, endDate) {
        if (!startDate || !endDate) {
            return false;
        }
        var start = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate());
        var end = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate());
        return end < start;
    }

    /* Shows or removes the error on the end date; returns true if the dates are consistent */
    function checkDates(formContext) {
        var control = formContext.getControl(END_DATE);
        var inconsistent = areDatesInconsistent(getAttributeValue(formContext, START_DATE), getAttributeValue(formContext, END_DATE));
        if (control) {
            if (inconsistent) {
                control.setNotification(MESSAGE, NOTIFICATION_ID);
            } else {
                control.clearNotification(NOTIFICATION_ID);
            }
        }
        return !inconsistent;
    }

    /* Form handlers */

    function onLoad(executionContext) {
        checkDates(executionContext.getFormContext());
    }

    function onDateChange(executionContext) {
        checkDates(executionContext.getFormContext());
    }

    function onSave(executionContext) {
        if (!checkDates(executionContext.getFormContext())) {
            executionContext.getEventArgs().preventDefault();
        }
    }

    return {
        onLoad: onLoad,
        onDateChange: onDateChange,
        onSave: onSave,
        areDatesInconsistent: areDatesInconsistent
    };
})();
