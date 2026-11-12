using System;
using System.Linq;
using Microsoft.Xrm.Sdk;

namespace Alchemist.Plugins
{
    /// <summary>
    /// Stores the account number in uppercase, without spaces (create and update of account). Trace texts are in the CRM language (French).
    /// </summary>
    public class AccountNumberNormalizationPlugin : IPlugin
    {
        private const string TargetKey = "Target";
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

            var accountNumber = target.GetAttributeValue<string>(AccountNumberAttribute);
            if (accountNumber == null)
            {
                return;
            }

            var normalized = Normalize(accountNumber);
            if (normalized.Length == 0)
            {
                tracing.Trace("Numéro de compte vide après normalisation : valeur conservée.");
                return;
            }

            tracing.Trace("Numéro de compte normalisé.");
            target[AccountNumberAttribute] = normalized;
        }

        internal static string Normalize(string value)
        {
            var withoutWhitespace = new string(value.Where(c => !char.IsWhiteSpace(c)).ToArray());
            return withoutWhitespace.ToUpperInvariant();
        }
    }
}
