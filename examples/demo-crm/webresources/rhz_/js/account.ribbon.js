/**
  * Commands and enable rules of the account table ribbon (dialog texts in the CRM language, French).
 * Web resource : rhz_/js/account.ribbon.js
  * Parameters provided by the ribbon: PrimaryControl, SelectedControl,
 * SelectedControlSelectedItemIds, SelectedControlSelectedItemCount.
 */
var Alchemist = window.Alchemist || {};
Alchemist.Account = Alchemist.Account || {};
Alchemist.Account.Ribbon = (function () {
    "use strict";

    var FORM_TYPE_CREATE = 1;
    var STATE_ACTIVE = 0;
    var watchedAttributes = {};

    function getAttributeValue(formContext, name) {
        var attribute = formContext.getAttribute(name);
        return attribute ? attribute.getValue() : null;
    }

    function getRecordId(formContext) {
        return formContext.data.entity.getId().replace(/[{}]/g, "");
    }

    function showError(error) {
        Xrm.Navigation.openErrorDialog({ message: error && error.message ? error.message : String(error) });
    }

    // Re-evaluates the rules when the field changes: the ribbon does not do it by itself.
    function watchAttribute(formContext, name) {
        var attribute = formContext.getAttribute(name);
        if (!attribute || watchedAttributes[name]) {
            return;
        }
        watchedAttributes[name] = true;
        attribute.addOnChange(function () {
            formContext.ui.refreshRibbon();
        });
    }

    /* Enable rules */

    function isExistingRecord(primaryControl) {
        return primaryControl.ui.getFormType() !== FORM_TYPE_CREATE;
    }

    function hasPhone(primaryControl) {
        watchAttribute(primaryControl, "telephone1");
        return !!getAttributeValue(primaryControl, "telephone1");
    }

    function hasWebsite(primaryControl) {
        watchAttribute(primaryControl, "websiteurl");
        return !!getAttributeValue(primaryControl, "websiteurl");
    }

    function hasLegalRep(primaryControl) {
        watchAttribute(primaryControl, "rhz_legalrepid");
        return !!getAttributeValue(primaryControl, "rhz_legalrepid");
    }

    // Asynchronous rule: the ribbon waits for the promise.
    function isActiveRecordAsync(primaryControl) {
        if (primaryControl.ui.getFormType() === FORM_TYPE_CREATE) {
            return Promise.resolve(false);
        }
        return Xrm.WebApi.retrieveRecord("account", getRecordId(primaryControl), "?$select=statecode")
            .then(function (record) {
                return record.statecode === STATE_ACTIVE;
            })
            .catch(function () {
                return false;
            });
    }

    function hasSelection(selectedCount) {
        return selectedCount >= 1;
    }

    function hasSingleSelection(selectedCount) {
        return selectedCount === 1;
    }

    /* Actions */

    function showAccountInfo(primaryControl) {
        var text = [
            "Name: " + (getAttributeValue(primaryControl, "name") || "-"),
            "Phone: " + (getAttributeValue(primaryControl, "telephone1") || "-"),
            "Website: " + (getAttributeValue(primaryControl, "websiteurl") || "-")
        ].join("\n");
        return Xrm.Navigation.openAlertDialog({ title: "Account information", text: text }).catch(showError);
    }

    function callAccount(primaryControl) {
        Xrm.Navigation.openUrl("tel:" + getAttributeValue(primaryControl, "telephone1"));
    }

    function notifyActive(primaryControl) {
        primaryControl.ui.setFormNotification("This account is active.", "INFO", "rhz_account_active");
        window.setTimeout(function () {
            primaryControl.ui.clearFormNotification("rhz_account_active");
        }, 5000);
    }

    function openWebsite(primaryControl) {
        Xrm.Navigation.openUrl(getAttributeValue(primaryControl, "websiteurl"));
    }

    function showLegalRep(primaryControl) {
        var legalRep = getAttributeValue(primaryControl, "rhz_legalrepid");
        var name = legalRep && legalRep.length ? legalRep[0].name : "-";
        return Xrm.Navigation.openAlertDialog({ title: "Représentant légal", text: name }).catch(showError);
    }

    function createRelatedContact(primaryControl) {
        var parameters = {
            parentcustomerid: getRecordId(primaryControl),
            parentcustomeridname: getAttributeValue(primaryControl, "name"),
            parentcustomeridtype: "account"
        };
        return Xrm.Navigation.openForm({ entityName: "contact", useQuickCreateForm: true }, parameters).catch(showError);
    }

    function showSelectionSummary(selectedIds) {
        var requests = selectedIds.map(function (id) {
            return Xrm.WebApi.retrieveRecord("account", id.replace(/[{}]/g, ""), "?$select=name");
        });
        return Promise.all(requests)
            .then(function (records) {
                var names = records.map(function (record) {
                    return record.name;
                });
                return Xrm.Navigation.openAlertDialog({
                    title: names.length + " account(s) selected",
                    text: names.join("\n")
                });
            })
            .catch(showError);
    }

    function refreshGrid(selectedControl) {
        selectedControl.refresh();
    }

    function openSelectedAccount(selectedIds) {
        return Xrm.Navigation.openForm({ entityName: "account", entityId: selectedIds[0] }).catch(showError);
    }

    return {
        isExistingRecord: isExistingRecord,
        hasPhone: hasPhone,
        hasWebsite: hasWebsite,
        hasLegalRep: hasLegalRep,
        isActiveRecordAsync: isActiveRecordAsync,
        hasSelection: hasSelection,
        hasSingleSelection: hasSingleSelection,
        showAccountInfo: showAccountInfo,
        callAccount: callAccount,
        notifyActive: notifyActive,
        openWebsite: openWebsite,
        showLegalRep: showLegalRep,
        createRelatedContact: createRelatedContact,
        showSelectionSummary: showSelectionSummary,
        refreshGrid: refreshGrid,
        openSelectedAccount: openSelectedAccount
    };
})();
