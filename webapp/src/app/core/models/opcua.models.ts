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

export interface Pipeline {
  name: string;
  status?: string;
  className?: string;
  dataSourceName?: string;
  mode?: string;
  nodes?: number;
  nodeNames?: string;
  enabled?: boolean;
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
