export interface OpcuaNode {
  displayName: string;
  nodeNs: number;
  nodeId: string | number;
  nodeIdType: number;
  nodeCategory: 'folder' | 'object' | 'variable' | 'property' | 'method' | 'view';
  referenceType: string;
  typeDefNs: number | string;
  typeDefId: number | string;
  hasChildren: boolean;
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
  name: string;
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
  rowCount?: number;
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
}

/** A single OPC UA server connection profile */
export interface ServerProfile {
  id: string;
  name: string;
  url: string;
  securityMode: number;
  username: string;
  password: string;
  certPath: string;
  keyPath: string;
  trustDir: string;
  crlDir: string;
  clientURI: string;
  rootNodeId: string;
  rootNodeNs: number;
}

export interface AppConfig {
  /** @deprecated Use servers[] instead. Kept for migration only. */
  serverUrl: string;
  /** @deprecated */
  securityMode: number;
  /** @deprecated */
  username: string;
  /** @deprecated */
  password: string;
  apiBaseUrl: string;
  apiUsername: string;
  apiPassword: string;
  /** @deprecated */
  certPath: string;
  /** @deprecated */
  keyPath: string;
  /** @deprecated */
  trustDir: string;
  /** @deprecated */
  crlDir: string;
  /** @deprecated */
  clientURI: string;
  /** @deprecated */
  rootNodeId: string;
  /** @deprecated */
  rootNodeNs: number;
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
  /** Populated by GET /schemas/:name only */
  columns?: SchemaColumn[];
  /** Names of the pipelines currently bound to this schema */
  usedBy: string[];
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
  columns: { displayName: string; inferredType?: string; relativePath?: string[]; nodeNs?: number }[];
}

export interface CreateSchemaResult {
  created: boolean;
  schemaClass: string;
  dataSourceName: string;
  tableName: string;
  columnCount: number;
  serialClasses: number;
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

