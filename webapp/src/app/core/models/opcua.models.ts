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
  [key: string]: any; // allow extra fields from API
}

export interface DeployRequest {
  nodes: SelectedNode[];
  className: string;
  dataSourceName: string;
  packagePath: string;
  mode: 'polling' | 'subscription';
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
