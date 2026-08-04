/**
 * One icon set and one colour map for every OPC UA tree in the app.
 *
 * There were three implementations across four placements, and they disagreed:
 * `Objects` was a blue folder in the explorer and amber everywhere else, variables
 * were `settings_input_component` in two trees and `label` in the third, objects
 * were `inventory_2` or `category`, properties `tune` or `tag`. A user moving
 * between screens had to relearn the same address space.
 *
 * Amber for containers, teal for readable values. That split is the one that
 * matters when picking columns: a variable can become a column, a folder cannot.
 */
import { TreeNode } from '../../core/models/opcua.models';

export function nodeIcon(node: Pick<TreeNode, 'nodeCategory'>): string {
  switch (node.nodeCategory) {
    case 'folder': return 'folder';
    case 'object': return 'inventory_2';
    case 'variable': return 'settings_input_component';
    case 'property': return 'tune';
    case 'method': return 'function';
    default: return 'circle';
  }
}

/**
 * @param selected when true the icon takes the selection colour, so a chosen row
 * reads as chosen regardless of what kind of node it is.
 */
export function nodeIconClass(node: Pick<TreeNode, 'nodeCategory'>, selected = false): string {
  if (selected) return 'text-primary';
  switch (node.nodeCategory) {
    case 'folder': return 'text-amber-500';
    case 'object': return 'text-amber-600';
    case 'variable': return 'text-tertiary';
    case 'property': return 'text-on-surface-muted';
    // Methods are callable, not readable — deliberately not the variable teal, so
    // they do not read as pickable columns.
    case 'method': return 'text-indigo-400';
    default: return 'text-on-surface-muted';
  }
}

/**
 * Human label for a node class, for tooltips and the ineligible-row explanation.
 * Matches the vocabulary `BrowseService` sends on the wire.
 */
export function nodeCategoryLabel(node: Pick<TreeNode, 'nodeCategory'>): string {
  switch (node.nodeCategory) {
    case 'folder': return 'Folder';
    case 'object': return 'Object';
    case 'variable': return 'Variable';
    case 'property': return 'Property';
    case 'method': return 'Method';
    default: return 'Node';
  }
}
