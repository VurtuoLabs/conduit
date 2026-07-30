/**
 * Accumulates the record data that will be handed to an agent.
 *
 * Two jobs, both about keeping the payload sane. It truncates long text so one runaway
 * email body cannot crowd out everything else, and it drops empty values so the agent is
 * not handed a wall of nulls to reason about. The result serializes to compact JSON.
 *
 * Every query feeding a builder must run WITH USER_MODE. See ConduitCaseContext.
 */
public with sharing class ConduitContext {
  /** Long text is cut here. Generous enough to keep meaning, short enough to stay bounded. */
  public static final Integer DEFAULT_TEXT_LIMIT = 1500;

  private final Map<String, Object> values = new Map<String, Object>();
  private final Integer textLimit;

  public ConduitContext() {
    this(DEFAULT_TEXT_LIMIT);
  }

  public ConduitContext(Integer textLimit) {
    this.textLimit = textLimit;
  }

  /** Adds a value, skipping blanks and empty collections. */
  public ConduitContext put(String key, Object value) {
    if (value == null) {
      return this;
    }
    if (value instanceof String) {
      String text = clip((String) value);
      if (String.isNotBlank(text)) {
        values.put(key, text);
      }
      return this;
    }
    if (value instanceof List<Object> && ((List<Object>) value).isEmpty()) {
      return this;
    }
    if (
      value instanceof Map<String, Object> &&
      ((Map<String, Object>) value).isEmpty()
    ) {
      return this;
    }
    values.put(key, value);
    return this;
  }

  /** Adds a date as an ISO-ish string. Agents handle these more reliably than raw datetimes. */
  public ConduitContext putDate(String key, Datetime value) {
    return value == null
      ? this
      : put(key, value.formatGmt('yyyy-MM-dd HH:mm:ss') + ' GMT');
  }

  public ConduitContext putDate(String key, Date value) {
    return value == null ? this : put(key, String.valueOf(value));
  }

  public Boolean isEmpty() {
    return values.isEmpty();
  }

  public Map<String, Object> toMap() {
    return values;
  }

  public String toJson() {
    return JSON.serializePretty(values);
  }

  /** Cuts overlong text and says so, so the agent knows the record continues. */
  private String clip(String text) {
    if (String.isBlank(text)) {
      return null;
    }
    String trimmed = text.trim();
    return trimmed.length() <= textLimit
      ? trimmed
      : trimmed.left(textLimit) + ' [truncated]';
  }
}
