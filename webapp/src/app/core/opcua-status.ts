/**
 * Human-readable OPC UA StatusCodes.
 *
 * Severity is the top two bits (Part 4, 7.34), so `severityOf` needs no table —
 * only the human string does. This covers the codes a browse/read path through
 * this adapter can realistically return; anything else falls back to severity
 * plus hex, which is still more use than a bare 10-digit integer.
 *
 * **Every value here was generated from `tools/schema/StatusCode.csv` in the
 * open62541 distribution** — the OPC Foundation's own machine-readable list, and
 * the same source the C++ layer's `OpcuaErrMsgs.cpp` builds its descriptions
 * from. Do not hand-edit a numeric value. A wrong mapping is worse than the raw
 * integer: it is a confident label for the wrong condition, which is the defect
 * class this whole pass exists to remove.
 *
 * `label` is the operator-facing phrasing. `name` is the spec identifier, worth
 * surfacing on hover because it is what appears in `Ens_Util.Log`, in the
 * Management Portal, and in any vendor documentation the user will search.
 */

export type Severity = 'good' | 'uncertain' | 'bad';

interface StatusEntry {
  /** The spec identifier, e.g. `BadAttributeIdInvalid`. */
  name: string;
  /** Operator-facing phrasing. */
  label: string;
}

const NAMES: Record<number, StatusEntry> = {
  // ── Good ──
  0x00000000: { name: 'Good', label: 'Good' },
  0x00960000: { name: 'GoodLocalOverride', label: 'Good — value has been overridden locally' },

  // ── Uncertain ──
  0x40000000: { name: 'Uncertain', label: 'Uncertain' },
  0x40900000: { name: 'UncertainLastUsableValue', label: 'Uncertain — nothing is updating this value any more' },
  0x40910000: { name: 'UncertainSubstituteValue', label: 'Uncertain — value was overwritten manually' },
  0x40920000: { name: 'UncertainInitialValue', label: 'Uncertain — still the initial value' },
  0x40930000: { name: 'UncertainSensorNotAccurate', label: 'Uncertain — sensor is at one of its limits' },
  0x40940000: { name: 'UncertainEngineeringUnitsExceeded', label: 'Uncertain — outside the range defined for this parameter' },
  0x40950000: { name: 'UncertainSubNormal', label: 'Uncertain — too few of its sources are Good' },

  // ── Bad: the node itself ──
  0x80000000: { name: 'Bad', label: 'Bad — the operation failed' },
  0x80330000: { name: 'BadNodeIdInvalid', label: 'Bad — node id syntax is not valid' },
  0x80340000: { name: 'BadNodeIdUnknown', label: 'Bad — no such node on this server' },
  0x80350000: { name: 'BadAttributeIdInvalid', label: 'Bad — attribute not supported for this node' },
  0x80370000: { name: 'BadIndexRangeNoData', label: 'Bad — no data in the requested index range' },
  0x803A0000: { name: 'BadNotReadable', label: 'Bad — not readable' },
  0x803C0000: { name: 'BadOutOfRange', label: 'Bad — value out of range' },
  0x803D0000: { name: 'BadNotSupported', label: 'Bad — operation not supported' },
  0x803E0000: { name: 'BadNotFound', label: 'Bad — not found' },
  0x80740000: { name: 'BadTypeMismatch', label: 'Bad — type mismatch' },
  0x809E0000: { name: 'BadDataUnavailable', label: 'Bad — data unavailable for the requested time range' },

  // ── Bad: the device or data source behind the node ──
  0x80310000: { name: 'BadNoCommunication', label: 'Bad — no communication with the data source' },
  0x80320000: { name: 'BadWaitingForInitialData', label: 'Bad — waiting for the first value from the data source' },
  0x808A0000: { name: 'BadNotConnected', label: 'Bad — never configured to receive a value' },
  0x808B0000: { name: 'BadDeviceFailure', label: 'Bad — device failure' },
  0x808C0000: { name: 'BadSensorFailure', label: 'Bad — sensor failure' },
  0x808D0000: { name: 'BadOutOfService', label: 'Bad — data source is not operational' },

  // ── Bad: session, transport and permissions ──
  0x80010000: { name: 'BadUnexpectedError', label: 'Bad — unexpected error' },
  0x80020000: { name: 'BadInternalError', label: 'Bad — internal error' },
  0x800A0000: { name: 'BadTimeout', label: 'Bad — timed out' },
  0x800C0000: { name: 'BadShutdown', label: 'Bad — server is shutting down' },
  0x800D0000: { name: 'BadServerNotConnected', label: 'Bad — not connected to the server' },
  0x800E0000: { name: 'BadServerHalted', label: 'Bad — server has stopped' },
  0x80100000: { name: 'BadTooManyOperations', label: 'Bad — too many operations in one request' },
  0x80130000: { name: 'BadSecurityChecksFailed', label: 'Bad — security check failed' },
  0x801F0000: { name: 'BadUserAccessDenied', label: 'Bad — access denied for this user' },
  0x80250000: { name: 'BadSessionIdInvalid', label: 'Bad — session id is not valid' },
  0x80260000: { name: 'BadSessionClosed', label: 'Bad — session was closed' },
  0x80AB0000: { name: 'BadInvalidArgument', label: 'Bad — invalid argument' },
  0x80AE0000: { name: 'BadConnectionClosed', label: 'Bad — network connection closed' },
};

/**
 * Severity from the top two bits: 0 Good, 1 Uncertain, 2/3 Bad.
 * Needs no lookup table, and therefore cannot be wrong for an unknown code.
 */
export function severityOf(code: number): Severity {
  const sev = (code >>> 30) & 0b11;
  return sev === 0 ? 'good' : sev === 1 ? 'uncertain' : 'bad';
}

/** `0x80350000` — the form an engineer can search for. */
export function hexOf(code: number): string {
  return '0x' + (code >>> 0).toString(16).toUpperCase().padStart(8, '0');
}

/**
 * Operator-facing text for a status code.
 *
 * For an unmapped code, states the severity — which is always derivable — and
 * the hex, rather than guessing at a meaning.
 */
export function statusText(code: number): string {
  const entry = NAMES[code >>> 0];
  if (entry) return entry.label;
  const sev = severityOf(code);
  const word = sev === 'good' ? 'Good' : sev === 'uncertain' ? 'Uncertain' : 'Bad';
  return `${word} — unrecognised status ${hexOf(code)}`;
}

/**
 * The spec identifier plus hex, for a `title` attribute. This is the string that
 * appears in the event log and in vendor documentation, so it is the useful thing
 * to be able to copy.
 */
export function statusDetail(code: number): string {
  const entry = NAMES[code >>> 0];
  return entry ? `${entry.name} (${hexOf(code)})` : hexOf(code);
}
