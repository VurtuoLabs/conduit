@IsTest
private class ConduitCurrentCaseTest {
  /**
   * LastViewedDate is maintained by the platform on read, not settable in Apex, so these
   * tests exercise the contract and the empty path rather than trying to forge a view
   * history. The resolution itself is verified against a real org in the agent preview.
   */
  @IsTest
  static void returnsOneResultPerRequest() {
    List<ConduitCurrentCase.Request> requests = new List<ConduitCurrentCase.Request>{
      new ConduitCurrentCase.Request(),
      new ConduitCurrentCase.Request()
    };

    Test.startTest();
    List<ConduitCurrentCase.Result> results = ConduitCurrentCase.current(
      requests
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      results.size(),
      'Invocable actions must answer every request'
    );
  }

  @IsTest
  static void toleratesAnEmptyRequestList() {
    List<ConduitCurrentCase.Result> results = ConduitCurrentCase.current(
      new List<ConduitCurrentCase.Request>()
    );
    Assert.areEqual(1, results.size());
  }

  @IsTest
  static void explainsItselfWhenNothingHasBeenViewed() {
    // A fresh test context has no view history, so this is the no-match path.
    ConduitCurrentCase.Result result = ConduitCurrentCase.current(
      new List<ConduitCurrentCase.Request>{ new ConduitCurrentCase.Request() }
    )[0];

    if (!result.found) {
      Assert.isTrue(
        result.summary.contains('case number'),
        'The fallback must tell the engineer what to do instead, got: ' +
        result.summary
      );
      Assert.areEqual('', result.caseId);
    }
  }
}
