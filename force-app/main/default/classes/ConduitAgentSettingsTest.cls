@IsTest
private class ConduitAgentSettingsTest {
  @IsTest
  static void overrideWinsSoTestsDoNotDependOnOrgRecords() {
    ConduitAgentSettings.agentApiNameOverride = 'Overridden_Agent';
    Assert.areEqual(
      'Overridden_Agent',
      ConduitAgentSettings.agentApiNameFor('Anything')
    );
  }

  @IsTest
  static void missingRecordExplainsWhereToCreateIt() {
    try {
      ConduitAgentSettings.agentApiNameFor(
        'No_Such_Use_Case_' + DateTime.now().getTime()
      );
      Assert.fail('Expected a ConduitException');
    } catch (ConduitAgentClient.ConduitException expected) {
      Assert.isTrue(
        expected.getMessage().contains('Custom Metadata Types'),
        'Error should say where to go'
      );
    }
  }
}
