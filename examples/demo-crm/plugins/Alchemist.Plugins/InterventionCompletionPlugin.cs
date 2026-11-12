using System;
using Microsoft.Xrm.Sdk;

namespace Alchemist.Plugins
{
    /// <summary>
    /// Completed intervention (create and update of rhz_intervention, PreOperation):
    /// refuses a missing or zero duration, then copies the intervention date to the equipment
    /// (rhz_datederniereintervention) without ever moving it backwards. User messages are in the CRM language (French).
    /// </summary>
    public class InterventionCompletionPlugin : IPlugin
    {
        private const string TargetKey = "Target";
        private const string PreImageKey = "PreImage";
        public const int StatusCompleted = 911240001;
        public const string DurationRequiredMessage = "Une intervention réalisée doit avoir une durée positive (en heures).";

        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var tracing = (ITracingService)serviceProvider.GetService(typeof(ITracingService));

            if (!context.InputParameters.Contains(TargetKey) || !(context.InputParameters[TargetKey] is Entity target))
            {
                return;
            }

            // Values after the operation: those of the target, otherwise those of the pre-image (update).
            var preImage = context.PreEntityImages.Contains(PreImageKey) ? context.PreEntityImages[PreImageKey] : null;
            var status = Merged<OptionSetValue>(target, preImage, "rhz_statutintervention")?.Value;
            var duration = Merged<decimal?>(target, preImage, "rhz_dureeheures");
            var date = Merged<DateTime?>(target, preImage, "rhz_dateintervention");
            var equipment = Merged<EntityReference>(target, preImage, "rhz_equipementid");

            if (status != StatusCompleted)
            {
                return;
            }

            if (!HasValidDuration(duration))
            {
                throw new InvalidPluginExecutionException(DurationRequiredMessage);
            }

            if (equipment == null || date == null)
            {
                tracing.Trace("Intervention réalisée sans équipement ou sans date : équipement non mis à jour.");
                return;
            }

            var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            var service = factory.CreateOrganizationService(context.UserId);
            var current = service.Retrieve(equipment.LogicalName, equipment.Id, new Microsoft.Xrm.Sdk.Query.ColumnSet("rhz_datederniereintervention"))
                .GetAttributeValue<DateTime?>("rhz_datederniereintervention");

            if (!ShouldUpdateLastIntervention(current, date.Value))
            {
                tracing.Trace("Date d'intervention antérieure ou égale à la dernière connue : équipement inchangé.");
                return;
            }

            var update = new Entity(equipment.LogicalName, equipment.Id);
            update["rhz_datederniereintervention"] = date.Value;
            service.Update(update);
            tracing.Trace("Dernière intervention de l'équipement mise à jour.");
        }

        public static bool HasValidDuration(decimal? duration) => duration.HasValue && duration.Value > 0m;

        public static bool ShouldUpdateLastIntervention(DateTime? current, DateTime interventionDate) =>
            !current.HasValue || interventionDate.Date > current.Value.Date;

        private static T Merged<T>(Entity target, Entity preImage, string attribute)
        {
            if (target.Contains(attribute))
            {
                return target.GetAttributeValue<T>(attribute);
            }
            return preImage != null && preImage.Contains(attribute) ? preImage.GetAttributeValue<T>(attribute) : default(T);
        }
    }
}
