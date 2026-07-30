import { createElement } from "lwc";
import ConduitCaseBrief from "c/conduitCaseBrief";
import generateBrief from "@salesforce/apex/ConduitCaseBriefController.generateBrief";
import askFollowUp from "@salesforce/apex/ConduitCaseBriefController.askFollowUp";

jest.mock(
  "@salesforce/apex/ConduitCaseBriefController.generateBrief",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ConduitCaseBriefController.askFollowUp",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("c-conduit-case-brief", () => {
  let element;

  beforeEach(() => {
    element = createElement("c-conduit-case-brief", { is: ConduitCaseBrief });
    element.recordId = "500000000000000AAA";
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // Lets the component's promise chain settle before assertions run.
  const settle = () => Promise.resolve().then(() => Promise.resolve());

  const clickPrimary = async () => {
    element.shadowRoot
      .querySelector('lightning-button[slot="actions"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();
  };

  it("does not call the agent on render", () => {
    document.body.appendChild(element);
    expect(generateBrief).not.toHaveBeenCalled();
  });

  it("passes the record id and renders the brief", async () => {
    generateBrief.mockResolvedValue({
      message: "Situation\nSign-in is failing.",
      sessionId: "session-1"
    });
    document.body.appendChild(element);

    await clickPrimary();

    expect(generateBrief).toHaveBeenCalledWith({
      caseId: "500000000000000AAA"
    });
    expect(
      element.shadowRoot.querySelector(".conduit-prose").textContent
    ).toContain("Sign-in is failing.");
  });

  it("sends the session id back on a follow-up", async () => {
    generateBrief.mockResolvedValue({
      message: "a brief",
      sessionId: "session-1"
    });
    askFollowUp.mockResolvedValue({
      message: "an answer",
      sessionId: "session-1"
    });
    document.body.appendChild(element);

    await clickPrimary();

    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    // The handler reads event.target.value, so the value goes on the element itself.
    textarea.value = "What is the SLA exposure?";
    textarea.dispatchEvent(new CustomEvent("change"));

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const ask = Array.from(buttons).find((b) => b.label === "Ask");
    ask.dispatchEvent(new CustomEvent("click"));
    await settle();

    expect(askFollowUp).toHaveBeenCalledWith({
      question: "What is the SLA exposure?",
      sessionId: "session-1"
    });
  });

  it("shows the Apex message rather than the raw error object", async () => {
    generateBrief.mockRejectedValue({
      body: { message: 'Conduit Agent setting "Case_Brief" is switched off.' }
    });
    document.body.appendChild(element);

    await clickPrimary();

    const error = element.shadowRoot.querySelector(".conduit-error");
    expect(error.textContent).toContain("is switched off.");
    expect(error.textContent).not.toContain("[object Object]");
  });

  it("clears earlier answers when the brief is regenerated", async () => {
    generateBrief.mockResolvedValue({
      message: "a brief",
      sessionId: "session-1"
    });
    askFollowUp.mockResolvedValue({
      message: "an answer",
      sessionId: "session-1"
    });
    document.body.appendChild(element);

    await clickPrimary();

    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    textarea.value = "why?";
    textarea.dispatchEvent(new CustomEvent("change"));
    const ask = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).find((b) => b.label === "Ask");
    ask.dispatchEvent(new CustomEvent("click"));
    await settle();

    expect(
      element.shadowRoot.querySelectorAll(".conduit-exchange").length
    ).toBe(1);

    generateBrief.mockResolvedValue({
      message: "a second brief",
      sessionId: "session-2"
    });
    await clickPrimary();

    expect(
      element.shadowRoot.querySelectorAll(".conduit-exchange").length
    ).toBe(0);
  });
});
