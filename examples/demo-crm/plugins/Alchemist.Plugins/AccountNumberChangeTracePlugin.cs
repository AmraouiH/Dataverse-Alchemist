using System;
using Microsoft.Xrm.Sdk;

namespace Alchemist.Plugins
{
    /// <summary>
    /// Traces the old and new account number (update of account, asynchronous). Trace texts are in the CRM language (French).
    /// </summary>
    public class AccountNumberChangeTracePlugin : IPlugin
    {
        private const string TargetKey = "Target";
        private const string PreImageKey = "PreImage";
        private const string AccountNumberAttribute = "accountnumber";

        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var tracing = (ITracingService)serviceProvider.GetService(typeof(ITracingService));

            if (!context.InputParameters.Contains(TargetKey) || !(context.InputParameters[TargetKey] is Entity target))
            {
                return;
            }

            if (!target.Contains(AccountNumberAttribute))
            {
                return;
            }

            var newValue = target.GetAttributeValue<string>(AccountNumberAttribute);

            string oldValue = null;
            if (context.PreEntityImages.Contains(PreImageKey))
            {
                oldValue = context.PreEntityImages[PreImageKey].GetAttributeValue<string>(AccountNumberAttribute);
            }
            else
            {
                tracing.Trace("Pré-image absente : ancienne valeur inconnue.");
            }

            tracing.Trace("Numéro de compte modifié : ancienne valeur « " + (oldValue ?? "(aucune)") + " », nouvelle valeur « " + (newValue ?? "(aucune)") + " ».");
        }
    }
}
