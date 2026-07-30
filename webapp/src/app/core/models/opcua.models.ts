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

export interface DeployRequest {
  nodes: SelectedNode[];
  className: string;
  dataSourceName: string;
  packagePath: string;
  mode: 'polling' | 'subscription';
}

/** v2 deploy payload: one pipeline with multiple row sources sharing the same schema */
export interface DeployV2Request {
  className: string;
  dataSourceName: string;
  mode: 'polling' | 'subscription';
  pipelineVersion: 2;
  columns: { displayName: string; inferredType?: string; relativePath?: string[] }[];
  rowSources: {
    displayName: string;
    nodeNs: number;
    nodeId: string | number;
    nodeIdType: number;
    path: string;
    childNodes: {
      displayName: string;
      nodeNs: number;
      nodeId: string | number;
      nodeIdType: number;
      relativePath?: string[];
    }[];
  }[];
}

export interface DeployResult {
  dataSourceClass: string;
  productionClass: string;
  tableName: string;
  deployed: boolean;
  compiled: boolean;
  started: boolean;
  error?: string;
}

export interface SelectedNode {
  displayName: string;
  nodeNs: number;
  nodeId: string | number;
  nodeIdType: number;
  path?: string;
  /** Path segments relative to root device, e.g. ["SubFolder", "TargetNode"] or ["Temperature"] */
  relativePath?: string[];
}

export interface ConnectionTestResult {
  url: string;
  connected: boolean;
  responseTimeMs: number;
  error?: string;
}

/** A column in a pipeline schema (attribute to read) */
export interface ColumnDef {
  displayName: string;
  nodeCategory: string;
  /** Path segments relative to root device, e.g. ["SubFolder", "TargetNode"] or ["Temperature"] */
  relativePath?: string[];
}

/** A parent node that produces one row per poll cycle */
export interface RowSource {
  displayName: string;
  nodeNs: number;
  nodeId: string | number;
  nodeIdType: number;
  path: string;
  childNodes: SelectedNode[];
  /** Which server profile this row source belongs to */
  serverId?: string;
}

/** A computed grouping: one or more row sources sharing the same column schema */
export interface PipelineGroup {
  schemaKey: string;
  columns: ColumnDef[];
  rowSources: RowSource[];
  /** Which server profile this group belongs to (all row sources in a group share the same server) */
  serverId?: string;
}

/** Internal selection entry tracking both the leaf node and its root device ancestor */
export interface V2Selection {
  node: SelectedNode;
  /** The root device (row source). For direct children this is the immediate parent;
   *  for nested nodes this is the deepest object ancestor whose parent is a folder. */
  parentNode: {
    displayName: string;
    nodeNs: number;
    nodeId: string | number;
    nodeIdType: number;
    path: string;
  };
  /** Which server profile this selection belongs to */
  serverId: string;
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
}

/** A device bound to a schema, expressed as an OPC UA nodepath plus a label. */
export interface DeviceBinding {
  /** e.g. "ns=2;s=Plant.AC1" */
  nodePath: string;
  /** NodePath column value; defaults to nodePath when blank */
  label: string;
  /** Last known validation outcome, if a dry run has been performed */
  validation?: DeviceValidation;
}

export interface Metric {
  name: string;
  labels: Record<string, string>;
  value: number | null;
  help?: string;
  type?: string;
  unit?: string;
}

export interface MetricsSnapshot {
  scrapedAt: string;
  metrics: Metric[];
}
