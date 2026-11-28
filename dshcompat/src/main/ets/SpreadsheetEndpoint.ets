import { ArgsShape, DshEndpoint } from './CompatTypes';

export const WORKSPACE_FILES_SPREADSHEET_ENDPOINT: string = 'workspaceFiles/spreadsheet';

/** DSHM core extension. Upstream compatibility tables remain generated from upstream descriptors. */
export const DSHM_SPREADSHEET_DESCRIPTOR: DshEndpoint = {
  id: '@deepseek-ai/dsh-api-workspace-files#workspaceFiles/spreadsheet',
  ns: 'workspaceFiles',
  method: 'spreadsheet',
  shape: ArgsShape.NAMED,
  params: ['workspaceFileScopeId', 'path'],
  stream: false,
  cancellable: true,
  source: 'hostcore/spreadsheet/service.mjs',
  capability: 'workspaceFiles',
  capabilities: ['workspaceFiles']
};
