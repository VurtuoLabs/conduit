import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import generateBrief from "@salesforce/apex/ConduitCaseBriefController.generateBrief";
import askFollowUp from "@salesforce/apex/ConduitCaseBriefController.askFollowUp";

/**
 * Renders an agent-written brief for the current case, then lets the user keep asking
 * questions against the same agent session.
 *
 * Nothing happens until the user clicks. Generating on load would spend an agent call every
 * time anyone so much as opened a case, including the ones nobody is working.
 */
export default class ConduitCaseBrief extends LightningElement {
  @api recordId;

  brief;
  errorMessage;
  isWorking = false;
  question = "";
  exchanges = [];

  /**
   * Held in component state on purpose. Apex statics do not survive between transactions,
   * so this is the only place the conversation thread exists.
   */
  sessionId;

  get hasBrief() {
    return Boolean(this.brief);
  }

  get hasExchanges() {
    return this.exchanges.length > 0;
  }

  get showIntro() {
    return !this.hasBrief && !this.isWorking && !this.errorMessage;
  }

  get primaryLabel() {
    return this.hasBrief ? "Regenerate" : "Write the brief";
  }

  // LWC templates cannot negate, so anything the markup consumes arrives in the polarity
  // the attribute needs.
  get isAskDisabled() {
    return this.isWorking || this.question.trim().length === 0;
  }

  get isBusy() {
    return this.isWorking;
  }

  async handleGenerate() {
    this.isWorking = true;
    this.errorMessage = undefined;
    try {
      const reply = await generateBrief({ caseId: this.recordId });
      this.brief = reply.message;
      this.sessionId = reply.sessionId;
      // A regenerated brief opens a new session, so old answers no longer belong to it.
      this.exchanges = [];
    } catch (error) {
      this.errorMessage = this.readError(error);
      this.brief = undefined;
      this.sessionId = undefined;
    } finally {
      this.isWorking = false;
    }
  }

  handleQuestionChange(event) {
    this.question = event.target.value;
  }

  async handleAsk() {
    if (this.isAskDisabled) {
      return;
    }
    const asked = this.question.trim();
    this.isWorking = true;
    this.errorMessage = undefined;
    try {
      const reply = await askFollowUp({
        question: asked,
        sessionId: this.sessionId
      });
      this.exchanges = [
        ...this.exchanges,
        {
          id: `${this.exchanges.length}-${Date.now()}`,
          question: asked,
          answer: reply.message
        }
      ];
      // The platform can hand back a different session id. Always take the latest.
      this.sessionId = reply.sessionId;
      this.question = "";
    } catch (error) {
      this.errorMessage = this.readError(error);
    } finally {
      this.isWorking = false;
    }
  }

  async handleCopy() {
    const text = [
      this.brief,
      ...this.exchanges.map((e) => `Q: ${e.question}\n\n${e.answer}`)
    ].join("\n\n---\n\n");
    try {
      await navigator.clipboard.writeText(text);
      this.toast("Copied", "The brief is on your clipboard.", "success");
    } catch {
      // The clipboard API needs a secure context and can be blocked by browser policy.
      this.toast(
        "Could not copy",
        "Select the text and copy it manually.",
        "warning"
      );
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  /**
   * Apex errors arrive wrapped. Without this the user is shown "[object Object]", which is
   * the single most common complaint about components that call Apex imperatively.
   */
  readError(error) {
    return (
      error?.body?.message ||
      error?.body?.pageErrors?.[0]?.message ||
      error?.message ||
      "Something went wrong and no reason was reported."
    );
  }
}
