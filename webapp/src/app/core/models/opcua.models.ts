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
  rowSources?: { path: string; nodeNs: number; nodeId: string | number; nodeIdType: number }[];
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
  columns: { displayName: string; inferredType?: string }[];
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
}

/** A parent node that produces one row per poll cycle */
export interface RowSource {
  displayName: string;
  nodeNs: number;
  nodeId: string | number;
  nodeIdType: number;
  path: string;
  childNodes: SelectedNode[];
}

/** A computed grouping: one or more row sources sharing the same column schema */
export interface PipelineGroup {
  schemaKey: string;
  columns: ColumnDef[];
  rowSources: RowSource[];
}

/** Internal selection entry tracking both the leaf node and its parent */
export interface V2Selection {
  node: SelectedNode;
  parentNode: {
    displayName: string;
    nodeNs: number;
    nodeId: string | number;
    nodeIdType: number;
    path: string;
  };
}

export interface AppConfig {
  serverUrl: string;
  securityMode: number;
  username: string;
  password: string;
  apiBaseUrl: string;
  apiUsername: string;
  apiPassword: string;
  certPath: string;
  keyPath: string;
  trustDir: string;
  crlDir: string;
  clientURI: string;
  rootNodeId: string;
  rootNodeNs: number;
  autoRefreshInterval: number;
}
