/**
 * Resolves which agent a given use case should talk to.
 *
 * Agent API names are org-specific, so hardcoding one guarantees the package breaks the
 * first time it is deployed anywhere other than where it was written. Conduit reads them
 * from Conduit_Agent__mdt instead, keyed by a stable use case name that the Apex refers to.
 */
public with sharing class ConduitAgentSettings {
  /** Test-only override, so tests do not depend on records existing in the org. */
  @TestVisible
  private static String agentApiNameOverride;

  /**
   * @param useCase DeveloperName of the Conduit_Agent__mdt record, for example Case_Brief.
   * @return The configured Agent API Name.
   */
  public static String agentApiNameFor(String useCase) {
    if (agentApiNameOverride != null) {
      return agentApiNameOverride;
    }

    Conduit_Agent__mdt setting = Conduit_Agent__mdt.getInstance(useCase);
    if (setting == null) {
      throw new ConduitAgentClient.ConduitException(
        'No Conduit Agent setting named "' +
          useCase +
          '". Create the record under Setup, Custom Metadata Types, Conduit Agent.'
      );
    }
    if (String.isBlank(setting.Agent_API_Name__c)) {
      throw new ConduitAgentClient.ConduitException(
        'Conduit Agent setting "' + useCase + '" has no Agent API Name.'
      );
    }
    if (!setting.Active__c) {
      throw new ConduitAgentClient.ConduitException(
        'Conduit Agent setting "' + useCase + '" is switched off.'
      );
    }
    return setting.Agent_API_Name__c;
  }
}
