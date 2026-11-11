/** UA_NodeClass, as reported by the server. `nodeClass` on the wire is the raw value. */
export const NodeClass = {
  Object: 1,
  Variable: 2,
  Method: 4,
  ObjectType: 8,
  VariableType: 16,
  ReferenceType: 32,
  DataType: 64,
  View: 128,
} as const;

export interface OpcuaNode {
  displayName: string;
  nodeNs: number;
  nodeId: string | number;
  nodeIdType: number;
  /**
   * This UI's categories, which are finer than OPC UA's node classes in places
   * (Object splits into folder/object, Variable into variable/property) and
   * coarser in others (a View is presented as a folder, so 'view' never arrives).
   */
  nodeCategory: 'folder' | 'object' | 'variable' | 'property' | 'method';
  referenceType: string;
  typeDefNs: number | string;
  typeDefId: number | string;
  hasChildren: boolean;
  /** Raw UA_NodeClass. '' from binaries that predate the C++ nodeClass export. */
  nodeClass?: number | '';
}

export interface TreeNode extends OpcuaNode {
  children?: TreeNode[];
  expanded?: boolean;
  loading?: boolean;
  selected?: boolean;
  level: number;
  parentRef?: TreeNode;
  /** Which server profile this node belongs to */
  serverId?: string;
  /** Why the last attempt to browse this node's children failed, or unset. */
  browseError?: string;
}

export interface NodeReadResult {
  nodeNs: number;
  nodeId: string;
  nodeIdType: number;
  value: any;
  sourceTimestamp?: string;
  serverTimestamp?: string;
  statusCode?: number;
  inferredType?: string;
  readError?: string;
}

/**
 * Whether a pipeline is actually collecting — which is not the same as being
 * enabled. A pipeline that can't connect or whose columns don't resolve stays
 * enabled and keeps retrying while writing nothing.
 */
export type PipelineHealth = 'ok' | 'error' | 'starting' | 'disabled' | 'stopped';

export interface Pipeline {
  /**
   * The `Ens.Config.Item` name — the interop identity, not a label. It is the
   * lookup key for toggle/rebind/delete, the key for health telemetry, and the
   * string an operator sees in `Ens_Util.Log` and the Management Portal.
   */
  name: string;
  /**
   * Portal categories (`Ens.Config.Item.Category`), already split and trimmed by
   * the backend. Organisational only — the Production Configuration page groups
   * by them and nothing in the runtime reads them back.
   */
  categories?: string[];
  /**
   * Completed cycles, from Ensemble's own per-host counter. Distinguishes a
   * pipeline that has just started from one that has been running dry — `ok`
   * health with zero rows means different things at 1 cycle and at 50.
   */
  cycles?: number;
  status?: string;
  className?: string;
  dataSourceName?: string;
  mode?: string;
  nodes?: number;
  nodeNames?: string;
  enabled?: boolean;
  /** Real collection health, from the adapter's own per-cycle verdict. */
  health?: PipelineHealth;
  lastActivity?: string;
  error?: string;
  /** null when the count could not be taken (shown as a dash, not 0). */
  rowCount?: number | null;
  interval?: number;
  callInterval?: number;
  serverUrl?: string;
  pipelineVersion?: number;
  rowSources?: {
    path: string;
    nodeNs: number;
    nodeId: string | number;
    nodeIdType: number;
    childNodes?: { displayName: string; nodeNs: number; nodeId: string | number; nodeIdType: number; relativePath?: string[] }[];
  }[];
  [key: string]: any; // allow extra fields from API
}

export interface DeployResult {
  dataSourceClass: string;
  productionClass: string;
  tableName: string;
  deployed: boolean;
  compiled: boolean;
  /**
   * Always false: a deploy creates the pipeline stopped, so that starting to
   * poll a live server is a separate, explicit act.
   */
  started: boolean;
  /** Always false, for the same reason. Start it from the Pipelines dashboard. */
  enabled?: boolean;
  error?: string;
}

export interface ConnectionTestResult {
  url: string;
  connected: boolean;
  responseTimeMs: number;
  error?: string;
  /** Present for managed Sign & Encrypt only. */
  security?: SecureReadiness;
}

export type SecurityDiagnosisCategory =
  | 'network' | 'noSecureEndpoint' | 'serverChanged' | 'hostMismatch'
  | 'uriInvalid' | 'timeInvalid' | 'clientNotApproved'
  | 'noIdentity' | 'identityInvalid' | 'notTrusted' | 'issuerMissing' | 'other';

export interface SecurityDiagnosis {
  category: SecurityDiagnosisCategory;
  message: string;
  clientFingerprint?: string;
}

export interface SecureReadiness {
  managed: boolean;
  identityReady: boolean;
  serverTrusted: boolean;
  diagnosis?: SecurityDiagnosis;
}

export interface IdentityIssue {
  code: string;
  message: string;
}

export interface IdentityImpact {
  pipelines: { namespace: string; name: string; url: string }[];
  servers: { key: string; url: string; label: string }[];
}

/** The IRIS instance's OPC UA client identity. Never carries key material. */
export interface IdentityStatus {
  configured: boolean;
  ready: boolean;
  source?: string;
  clientURI?: string;
  fingerprint?: string;
  subject?: string;
  notBefore?: string;
  notAfter?: string;
  daysLeft?: number;
  errors: IdentityIssue[];
  warnings: IdentityIssue[];
  candidates?: { certPath: string; keyPath: string; clientURI: string; fingerprint: string; notAfter: string; ready: boolean }[];
  impact?: IdentityImpact;
  advanced?: { certPath: string; keyPath: string; storeRoot: string };
}

export interface CertificateSummary {
  subject: string;
  issuer: string;
  notBefore: string;
  notAfter: string;
  sha256: string;
  sanUris: string[];
  sanDns: string[];
  sanIps: string[];
  selfSigned: boolean;
}

/** What IRIS found on a server, for the user to review before trusting it. */
export interface ServerCertificateReview {
  url: string;
  key: string;
  offersSignAndEncrypt: boolean;
  policies: string[];
  applicationUri: string;
  certificate: CertificateSummary;
  identity: { uriMatches: boolean; hostMatches: boolean; problems: string[] };
  trusted: boolean;
  pinnedFingerprint: string;
  changed: boolean;
  /** The certificate is CA-signed, so an issuer certificate and CRL are required. */
  needsIssuer: boolean;
  /** An issuer certificate and CRL have been added. */
  hasIssuer: boolean;
  issuerName: string;
  previous?: CertificateSummary;
}

export interface TrustedServer {
  key: string;
  url: string;
  label?: string;
  fingerprint?: string;
  subject?: string;
  notAfter?: string;
  daysLeft?: number;
  needsIssuer?: boolean;
  hasIssuer?: boolean;
}

export interface IdentityReplaceGuard {
  replace?: boolean;
  currentFingerprint?: string;
}

export interface CreateIdentityRequest extends IdentityReplaceGuard {
  clientURI?: string;
}

/** Hex fields are uppercase. Key and password exist only for this request. */
export interface ImportIdentityRequest extends IdentityReplaceGuard {
  certificate?: string;
  key?: string;
  pkcs12?: string;
  password?: string;
}

export interface UseIdentityFilesRequest extends IdentityReplaceGuard {
  certPath: string;
  keyPath: string;
}

/** A single OPC UA server connection profile */
export interface ServerProfile {
  id: string;
  name: string;
  url: string;
  securityMode: number;
  /**
   * ID of the IRIS credentials entry (Ens.Config.Credentials) holding this server's
   * username and password, or '' for an anonymous session. The password itself is
   * never in the browser: the API reads the entry on the server, and deploy puts the
   * same ID in the pipeline, so the console and its pipelines share one entry.
   */
  credentials: string;
  certPath?: string;
  keyPath?: string;
  trustDir?: string;
  crlDir?: string;
  clientURI?: string;
}

/**
 * A Sign & Encrypt profile with no certificate or key path is managed: IRIS uses its
 * own client identity and trust store, so the console sends no certificate fields.
 */
export function isManaged(server: ServerProfile): boolean {
  return server.securityMode === 3 && !server.certPath && !server.keyPath;
}

/**
 * Where every address-space browse starts: the Root folder, ns=0;i=84. The OPC UA
 * spec fixes this node for every server, so it is not a per-server setting.
 */
export const ROOT_NODE = { ns: 0, id: 84 } as const;

export interface AppConfig {
  /** @deprecated Use servers[] instead. Kept for migration only. */
  serverUrl: string;
  /** @deprecated */
  securityMode: number;
  apiBaseUrl: string;
  /** The last account signed in with, to prefill the sign-in. Never its password. */
  apiUsername: string;
  /** @deprecated */
  certPath?: string;
  /** @deprecated */
  keyPath?: string;
  /** @deprecated */
  trustDir?: string;
  /** @deprecated */
  crlDir?: string;
  /** @deprecated */
  clientURI?: string;
  autoRefreshInterval: number;
  servers: ServerProfile[];
}

/** A reusable device schema: the columns of one device type, with no device binding. */
export interface Schema {
  schemaClass: string;
  name: string;
  packagePath: string;
  tableName: string;
  dataSourceName?: string;
  defaultNamespace?: number;
  columnCount: number;
  /** Why the columns could not be read; columnCount is then 0. */
  columnsError?: string;
  /** Populated by GET /schemas/:name only */
  columns?: SchemaColumn[];
  /** Pipelines currently bound to this schema, across all productions */
  usedBy: SchemaUsage[];
}

export interface SchemaUsage {
  /** Service item name */
  name: string;
  /** Production class name */
  production: string;
  /** True if production is OPCUA.Pipeline.Production (managed by console) */
  managed: boolean;
}

export interface SchemaColumn {
  nodeName: string;
  namespace: number;
  attributeId: number;
  /** Enclosing %SerialObject folder, or "" for a top-level column */
  folder: string;
  propertyPath: string;
}

export interface CreateSchemaRequest {
  name: string;
  packagePath?: string;
  dataSourceName?: string;
  defaultNamespace?: number;
  /** Default true. false: columns have no ServerTimeStamp, in the class or in SQL */
  includeServerTimestamp?: boolean;
  columns: { displayName: string; inferredType?: string; relativePath?: string[]; nodeNs?: number }[];
}

export interface CreateSchemaResult {
  created: boolean;
  schemaClass: string;
  dataSourceName: string;
  tableName: string;
  columnCount: number;
  serialClasses: number;
  includeServerTimestamp: boolean;
}

/** Per-device outcome of a dry-run binding check against a live server. */
export interface SchemaValidation {
  schemaClass: string;
  columnCount: number;
  devices: DeviceValidation[];
  allResolved: boolean;
  diagnostics: { device: string; column: string; reason: string }[];
}

export interface DeviceValidation {
  label: string;
  nodeNs: number;
  nodeId: string | number;
  matched: string[];
  missing: string[];
  matchedCount: number;
  missingCount: number;
  complete: boolean;
  /** Did the server answer the browse? False means unreachable or bad NodeId. */
  browsed: boolean;
  /**
   * Browsed successfully AND matched at least one column. A device that fails
   * this cannot be bound: it would only ever contribute all-NULL rows.
   */
  usable: boolean;
  /** Present when `usable` is false — why, in a form fit to show the user. */
  unusableReason?: string;
}

/** An IRIS credentials entry, as GET /credentials lists it. Never carries a password. */
export interface CredentialsEntry {
  id: string;
  username: string;
  /** Production items whose Credentials setting names it, as "Item (Production)". */
  usedBy: string[];
  /** The pipeline deploy made the entry for (deleting the pipeline deletes it), or ''. */
  pipeline: string;
}
