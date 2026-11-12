using System;
using Alchemist.Plugins;
using Xunit;

namespace Alchemist.Plugins.Tests
{
    public class InterventionCompletionPluginTests
    {
        [Theory]
        [InlineData(null, false)]
        [InlineData(0.0, false)]
        [InlineData(-1.5, false)]
        [InlineData(0.25, true)]
        [InlineData(8.0, true)]
        public void HasValidDuration_RejectsMissingOrNonPositive(double? hours, bool expected)
        {
            decimal? duration = hours.HasValue ? (decimal?)Convert.ToDecimal(hours.Value) : null;
            Assert.Equal(expected, InterventionCompletionPlugin.HasValidDuration(duration));
        }

        [Fact]
        public void ShouldUpdate_NoKnownDate_Updates()
        {
            Assert.True(InterventionCompletionPlugin.ShouldUpdateLastIntervention(null, new DateTime(2026, 3, 1)));
        }

        [Fact]
        public void ShouldUpdate_MoreRecentDate_Updates()
        {
            Assert.True(InterventionCompletionPlugin.ShouldUpdateLastIntervention(new DateTime(2026, 3, 1), new DateTime(2026, 3, 2)));
        }

        [Fact]
        public void ShouldUpdate_EarlierDate_DoesNotMoveBack()
        {
            Assert.False(InterventionCompletionPlugin.ShouldUpdateLastIntervention(new DateTime(2026, 3, 10), new DateTime(2026, 3, 2)));
        }

        [Fact]
        public void ShouldUpdate_SameDayOtherTime_DoesNotChange()
        {
            Assert.False(InterventionCompletionPlugin.ShouldUpdateLastIntervention(new DateTime(2026, 3, 10, 0, 0, 0), new DateTime(2026, 3, 10, 15, 30, 0)));
        }
    }
}
