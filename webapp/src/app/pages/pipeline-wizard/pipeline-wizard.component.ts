import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { TreeNode, OpcuaNode, SelectedNode } from '../../core/models/opcua.models';

@Component({
  selector: 'app-pipeline-wizard',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="p-8 max-w-7xl mx-auto w-full">
      <!-- Stepper -->
      <div class="flex items-center justify-between mb-12 max-w-4xl mx-auto relative">
        <div class="absolute top-1/2 left-0 w-full h-0.5 bg-outline-variant/20 -translate-y-1/2 z-0">
          <div class="h-full bg-primary transition-all" [style.width.%]="stepProgress()"></div>
        </div>
        @for (step of steps; track step.num; let i = $index) {
          <div class="relative z-10 flex flex-col items-center group">
            <div class="w-10 h-10 rounded-full flex items-center justify-center font-bold ring-4 ring-background transition-all"
                 [class]="i < currentStep()
                   ? 'bg-primary text-on-primary shadow-xl shadow-primary/20'
                   : i === currentStep()
                     ? 'bg-primary text-on-primary shadow-xl shadow-primary/20 ring-primary-fixed'
                     : 'bg-surface-dim text-on-surface-variant'">
              @if (i < currentStep()) {
                <span class="material-symbols-outlined text-base" style="font-variation-settings: 'FILL' 0, 'wght' 700;">check</span>
              } @else {
                {{ step.num }}
              }
            </div>
            <span class="absolute top-12 text-xs font-bold uppercase tracking-tighter transition-colors"
                  [class]="i <= currentStep() ? 'text-primary' : 'text-on-surface-variant'">
              {{ step.label }}
            </span>
          </div>
        }
      </div>

      <!-- Step Content -->
      <div class="mt-16">
        <!-- STEP 1: SELECT NODES -->
        @if (currentStep() === 0) {
          <div class="grid grid-cols-12 gap-8">
            <!-- Left: Node Selection Tree -->
            <div class="col-span-4 bg-surface-container-low rounded-xl p-6 shadow-sm min-h-[500px] overflow-y-auto custom-scrollbar">
              <div class="flex items-center justify-between mb-6">
                <h3 class="text-on-surface font-semibold text-sm">OPC UA Address Space</h3>
                <span class="material-symbols-outlined text-on-surface-variant text-lg cursor-pointer">filter_list</span>
              </div>
              <div class="relative mb-6">
                <span class="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-on-surface-variant text-sm">search</span>
                <input type="text" [(ngModel)]="searchQuery"
                       class="w-full bg-surface-container-lowest border-none ring-1 ring-outline-variant/20 rounded-lg pl-9 py-2 text-sm focus:ring-primary focus:ring-2 transition-all"
                       placeholder="Search nodes...">
              </div>
              <!-- Tree -->
              <div class="space-y-0.5 text-slate-700 select-none">
                @if (treeLoading()) {
                  <div class="flex items-center gap-2 p-2 text-on-surface-variant">
                    <span class="material-symbols-outlined text-sm animate-spin">progress_activity</span>
                    <span class="text-xs">Loading...</span>
                  </div>
                }
                @for (node of treeRoots(); track wizardNodeKey(node)) {
                  <ng-container *ngTemplateOutlet="wizardTreeTpl; context: { $implicit: node, level: 0 }" />
                }
              </div>
            </div>

            <!-- Right: Selection Area -->
            <div class="col-span-8 flex flex-col items-center justify-center p-12 bg-surface-container-lowest rounded-xl shadow-sm border border-outline-variant/10">
              <div class="mb-8 relative">
                <div class="w-48 h-48 rounded-3xl bg-surface-container-low flex items-center justify-center overflow-hidden">
                  <div class="absolute inset-0 bg-gradient-to-tr from-primary/5 to-transparent"></div>
                  <div class="flex flex-col gap-2 relative z-10">
                    <div class="flex gap-2">
                      <div class="w-12 h-12 rounded-lg flex items-center justify-center shadow-lg"
                           [class]="selectedNodes().length > 0 ? 'bg-primary text-on-primary' : 'bg-primary/10 border border-primary/20'">
                        <span class="material-symbols-outlined">{{ selectedNodes().length > 0 ? 'bar_chart' : 'data_object' }}</span>
                      </div>
                      <div class="w-12 h-12 rounded-lg bg-surface-variant/30 border border-outline-variant/20"></div>
                    </div>
                    <div class="flex gap-2 ml-4">
                      <div class="w-12 h-12 rounded-lg bg-surface-variant/30 border border-outline-variant/20"></div>
                      <div class="w-12 h-12 rounded-lg bg-primary/10 border border-primary/20 flex items-center justify-center">
                        <div class="w-2 h-2 rounded-full bg-primary animate-pulse"></div>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="absolute -bottom-4 left-1/2 -translate-x-1/2 bg-tertiary-fixed px-4 py-1.5 rounded-full shadow-lg border-4 border-surface-container-lowest">
                  <span class="text-xs font-bold text-on-tertiary-fixed uppercase tracking-wider">{{ selectedNodes().length }} node{{ selectedNodes().length !== 1 ? 's' : '' }} selected</span>
                </div>
              </div>

              <h1 class="text-2xl font-semibold text-on-surface mb-3 tracking-tight mt-8">Select Data Nodes</h1>
              <p class="text-on-surface-variant text-center max-w-md mb-10 text-sm leading-relaxed">
                Browse the OPC UA address space on the left to identify specific sensors, tags, or industrial components you wish to monitor in this pipeline.
              </p>
              <div class="flex items-center gap-4">
                <button (click)="nextStep()"
                        [disabled]="selectedNodes().length === 0"
                        class="px-8 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all disabled:opacity-40 disabled:cursor-not-allowed">
                  Review Selection
                  <span class="material-symbols-outlined">arrow_forward</span>
                </button>
                <button (click)="cancel()"
                        class="px-6 py-3 bg-surface-container-high text-on-surface-variant font-semibold rounded-lg hover:bg-surface-variant transition-colors">
                  Cancel
                </button>
              </div>

              <!-- Selected node preview cards -->
              @for (sel of selectedNodes(); track sel.nodeId) {
                <div class="mt-4 w-full max-w-lg p-4 bg-surface-container-low rounded-xl flex items-center gap-4 border border-outline-variant/10">
                  <div class="w-12 h-12 rounded-lg bg-white flex items-center justify-center text-primary shadow-sm">
                    <span class="material-symbols-outlined">bar_chart</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Selected Component</p>
                    <h4 class="text-sm font-semibold text-on-surface truncate">{{ sel.displayName }}</h4>
                    <p class="text-[10px] text-on-surface-variant font-mono">ns={{ sel.nodeNs }};{{ sel.nodeIdType === 0 ? 'i' : 's' }}={{ sel.nodeId }}</p>
                  </div>
                  <span class="material-symbols-outlined text-error cursor-pointer hover:bg-error-container/20 p-2 rounded-full transition-colors"
                        (click)="removeSelectedNode(sel)">close</span>
                </div>
              }
            </div>
          </div>

          <!-- Footer Meta -->
          <div class="mt-12 flex justify-between items-center text-on-surface-variant">
            <div class="flex items-center gap-6">
              <div class="flex flex-col">
                <span class="text-[10px] font-bold uppercase tracking-widest">Source Server</span>
                <span class="text-xs font-medium">{{ config.get().serverUrl || 'Not configured' }}</span>
              </div>
              <div class="w-[1px] h-8 bg-outline-variant/30"></div>
              <div class="flex flex-col">
                <span class="text-[10px] font-bold uppercase tracking-widest">Security Policy</span>
                <span class="text-xs font-medium">{{ config.get().securityMode === 3 ? 'Sign & Encrypt' : 'None' }}</span>
              </div>
            </div>
          </div>
        }

        <!-- STEP 2: REVIEW -->
        @if (currentStep() === 1) {
          <div class="max-w-3xl mx-auto">
            <h1 class="text-2xl font-semibold text-on-surface mb-6 tracking-tight">Review Selected Nodes</h1>
            <div class="space-y-3 mb-8">
              @for (sel of selectedNodes(); track sel.nodeId) {
                <div class="p-4 bg-surface-container-lowest rounded-xl flex items-center gap-4 border border-outline-variant/10 shadow-sm">
                  <div class="w-10 h-10 rounded-lg bg-secondary-container/50 flex items-center justify-center text-primary">
                    <span class="material-symbols-outlined">settings_input_component</span>
                  </div>
                  <div class="flex-1">
                    <p class="text-sm font-semibold text-on-surface">{{ sel.displayName }}</p>
                    <p class="text-xs text-on-surface-variant font-mono">ns={{ sel.nodeNs }};{{ sel.nodeIdType === 0 ? 'i' : 's' }}={{ sel.nodeId }}</p>
                  </div>
                </div>
              }
            </div>
            <div class="flex items-center gap-4">
              <button (click)="prevStep()"
                      class="px-6 py-3 text-primary font-bold hover:bg-white/50 rounded-lg transition-colors border border-outline-variant/20 flex items-center gap-2">
                <span class="material-symbols-outlined text-sm">arrow_back</span>
                Back
              </button>
              <button (click)="nextStep()"
                      class="px-8 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
                Continue to Configure
                <span class="material-symbols-outlined">arrow_forward</span>
              </button>
            </div>
          </div>
        }

        <!-- STEP 3: CONFIGURE -->
        @if (currentStep() === 2) {
          <div class="grid grid-cols-1 md:grid-cols-12 gap-8">
            <div class="md:col-span-8 space-y-8">
              <!-- Connection Settings (read-only) -->
              <section class="bg-surface-container-lowest rounded-xl p-8 shadow-sm">
                <div class="flex items-center gap-3 mb-6">
                  <span class="material-symbols-outlined text-primary">hub</span>
                  <h2 class="text-xl font-semibold tracking-tight">Connection Settings</h2>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div class="space-y-1">
                    <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">OPC UA Server</label>
                    <div class="p-3 bg-surface-container-low rounded-lg text-sm font-medium flex items-center justify-between">
                      {{ config.get().serverUrl || 'Not set' }}
                      <span class="material-symbols-outlined text-xs text-outline">lock</span>
                    </div>
                  </div>
                  <div class="space-y-1">
                    <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Security Policy</label>
                    <div class="p-3 bg-surface-container-low rounded-lg text-sm font-medium">
                      {{ config.get().securityMode === 3 ? 'Basic256Sha256 / Sign & Encrypt' : 'None' }}
                    </div>
                  </div>
                </div>
              </section>

              <!-- DataSource Class -->
              <section class="bg-surface-container-lowest rounded-xl p-8 shadow-sm">
                <div class="flex items-center gap-3 mb-6">
                  <span class="material-symbols-outlined text-primary">account_tree</span>
                  <h2 class="text-xl font-semibold tracking-tight">DataSource Class</h2>
                </div>
                <div class="space-y-6">
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div class="space-y-1">
                      <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Package Path</label>
                      <input type="text" [(ngModel)]="packagePath"
                             class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3"
                             placeholder="OPCUA.DS">
                    </div>
                    <div class="space-y-1">
                      <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Class Name</label>
                      <input type="text" [(ngModel)]="className"
                             class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3"
                             placeholder="MyDataSource">
                    </div>
                  </div>
                  <div class="space-y-1">
                    <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Data Source Name</label>
                    <input type="text" [(ngModel)]="dataSourceName"
                           class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3"
                           placeholder="Production_Line_1">
                  </div>
                </div>
              </section>

              <!-- Pipeline Mode -->
              <section class="bg-surface-container-lowest rounded-xl p-8 shadow-sm">
                <div class="flex items-center gap-3 mb-6">
                  <span class="material-symbols-outlined text-primary">sync_alt</span>
                  <h2 class="text-xl font-semibold tracking-tight">Pipeline Mode</h2>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <label class="relative flex cursor-pointer rounded-xl bg-surface-container-low p-4 focus:outline-none border-2 transition-all"
                         [class]="pipelineMode === 'polling' ? 'border-primary' : 'border-transparent'">
                    <input type="radio" name="mode" value="polling" [(ngModel)]="pipelineMode" class="sr-only">
                    <span class="flex flex-col">
                      <span class="text-sm font-bold text-on-surface">Polling</span>
                      <span class="text-xs text-on-surface-variant mt-1">Periodic requests at defined intervals (Recommended for legacy PLCs).</span>
                    </span>
                  </label>
                  <label class="relative flex cursor-pointer rounded-xl bg-surface-container-low p-4 focus:outline-none border-2 transition-all"
                         [class]="pipelineMode === 'subscription' ? 'border-primary' : 'border-transparent'">
                    <input type="radio" name="mode" value="subscription" [(ngModel)]="pipelineMode" class="sr-only">
                    <span class="flex flex-col">
                      <span class="text-sm font-bold text-on-surface">Subscription</span>
                      <span class="text-xs text-on-surface-variant mt-1">Event-driven data reporting (Lower bandwidth, higher efficiency).</span>
                    </span>
                  </label>
                </div>
              </section>
            </div>

            <!-- Right sidebar -->
            <div class="md:col-span-4 space-y-6">
              <div class="bg-surface-container rounded-xl p-6 sticky top-24">
                <h3 class="text-sm font-bold uppercase tracking-widest mb-6">Deployment Action</h3>
                <div class="flex items-start gap-3 p-4 bg-surface-container-lowest rounded-xl mb-8">
                  <input type="checkbox" [(ngModel)]="autoStart"
                         class="mt-1 w-5 h-5 text-primary border-outline-variant/40 rounded-md focus:ring-primary">
                  <label class="text-sm font-medium leading-relaxed cursor-pointer select-none">
                    Start pipeline after deploy
                    <p class="text-xs text-on-surface-variant font-normal mt-1">Initialize telemetry stream immediately after successful configuration.</p>
                  </label>
                </div>
                <div class="space-y-3">
                  <button (click)="deploy()"
                          [disabled]="deploying() || !className || !dataSourceName"
                          class="w-full py-4 bg-gradient-to-br from-primary to-primary-container text-on-primary rounded-xl font-bold shadow-lg shadow-primary/20 active:scale-95 transition-all flex items-center justify-center gap-2 disabled:opacity-40">
                    {{ deploying() ? 'Deploying...' : 'Deploy Pipeline' }}
                    <span class="material-symbols-outlined text-sm filled">rocket_launch</span>
                  </button>
                  <button (click)="prevStep()"
                          class="w-full py-4 text-primary font-bold hover:bg-white/50 rounded-xl transition-colors border border-outline-variant/20 flex items-center justify-center gap-2">
                    <span class="material-symbols-outlined text-sm">arrow_back</span>
                    Back to Review
                  </button>
                </div>
                @if (deployError()) {
                  <div class="mt-4 p-3 bg-error-container/20 text-error rounded-lg text-xs">
                    {{ deployError() }}
                  </div>
                }
              </div>
            </div>
          </div>
        }

        <!-- STEP 4: DEPLOY RESULT -->
        @if (currentStep() === 3) {
          <div class="max-w-2xl mx-auto text-center">
            <div class="w-24 h-24 mx-auto mb-8 rounded-full flex items-center justify-center"
                 [class]="deploySuccess() ? 'bg-tertiary-fixed text-tertiary' : 'bg-error-container text-error'">
              <span class="material-symbols-outlined text-5xl">{{ deploySuccess() ? 'check_circle' : 'error' }}</span>
            </div>
            <h1 class="text-3xl font-semibold mb-4">{{ deploySuccess() ? 'Pipeline Deployed' : 'Deployment Failed' }}</h1>
            <p class="text-on-surface-variant mb-8">{{ deployMessage() }}</p>
            <button (click)="finish()"
                    class="px-8 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 hover:brightness-110 active:scale-95 transition-all">
              Go to Pipelines
            </button>
          </div>
        }
      </div>
    </div>

    <!-- Wizard tree template (recursive) -->
    <ng-template #wizardTreeTpl let-node let-level="level">
      <div [style.padding-left.rem]="level * 1.25">
        <div class="flex items-center gap-1.5 p-1 rounded cursor-pointer transition-colors"
             [class]="isNodeSelected(node) ? 'bg-primary/5 border-y border-primary/10' : 'hover:bg-white/50'"
             (click)="onWizardNodeClick(node)">
          <!-- Checkbox for selectable nodes (variables) -->
          @if (node.nodeCategory === 'variable' || node.nodeCategory === 'object') {
            <input type="checkbox" [checked]="isNodeSelected(node)"
                   (click)="$event.stopPropagation()"
                   (change)="toggleNodeSelection(node)"
                   class="w-3.5 h-3.5 rounded border-slate-300 text-primary focus:ring-primary mr-1">
          }

          <!-- Expand arrow -->
          @if (node.hasChildren) {
            <span class="material-symbols-outlined text-lg"
                  [class]="isNodeSelected(node) ? 'text-primary' : 'text-slate-400'">
              {{ node.expanded ? 'arrow_drop_down' : 'arrow_right' }}
            </span>
          }

          <!-- Icon -->
          <span class="material-symbols-outlined text-lg"
                [class.filled]="node.nodeCategory === 'folder'"
                [class]="getWizardNodeIconClass(node)">
            {{ getWizardNodeIcon(node) }}
          </span>

          <!-- Label -->
          <span class="text-sm" [class]="isNodeSelected(node) ? 'font-bold text-primary' : ''">
            {{ node.displayName }}
          </span>
        </div>

        <!-- Children -->
        @if (node.expanded && node.children) {
          @if (node.loading) {
            <div [style.padding-left.rem]="(level + 1) * 1.25" class="flex items-center gap-2 p-1 text-on-surface-variant">
              <span class="material-symbols-outlined text-xs animate-spin">progress_activity</span>
              <span class="text-[11px]">Loading...</span>
            </div>
          }
          @for (child of node.children; track wizardNodeKey(child)) {
            <ng-container *ngTemplateOutlet="wizardTreeTpl; context: { $implicit: child, level: level + 1 }" />
          }
        }
      </div>
    </ng-template>
  `,
})
export class PipelineWizardComponent {
  private api = inject(ApiService);
  private router = inject(Router);
  config = inject(ConfigService);

  steps = [
    { num: 1, label: 'Select' },
    { num: 2, label: 'Review' },
    { num: 3, label: 'Configure' },
    { num: 4, label: 'Deploy' },
  ];

  currentStep = signal(0);
  stepProgress = signal(0);

  // Step 1: Tree & selection
  treeRoots = signal<TreeNode[]>([]);
  treeLoading = signal(false);
  selectedNodes = signal<SelectedNode[]>([]);
  searchQuery = '';

  // Step 3: Configure
  packagePath = 'OPCUA.DS';
  className = '';
  dataSourceName = '';
  pipelineMode: 'polling' | 'subscription' = 'polling';
  autoStart = true;

  // Step 4: Deploy
  deploying = signal(false);
  deployError = signal('');
  deploySuccess = signal(false);
  deployMessage = signal('');

  constructor() {
    this.loadTree();
  }

  loadTree(): void {
    const cfg = this.config.get();
    if (!cfg.apiBaseUrl || !cfg.serverUrl) return;
    this.treeLoading.set(true);
    this.api.browse(cfg.rootNodeNs, cfg.rootNodeId, undefined).subscribe({
      next: (nodes) => {
        this.treeRoots.set(nodes.map((n) => ({ ...n, level: 0 })));
        this.treeLoading.set(false);
      },
      error: () => this.treeLoading.set(false),
    });
  }

  wizardNodeKey(node: TreeNode): string {
    return `${node.nodeNs}:${node.nodeId}:${node.nodeIdType}`;
  }

  onWizardNodeClick(node: TreeNode): void {
    if (node.hasChildren) {
      if (node.expanded) {
        node.expanded = false;
        this.treeRoots.update((r) => [...r]);
        return;
      }
      node.expanded = true;
      if (node.children && node.children.length > 0) {
        this.treeRoots.update((r) => [...r]);
        return;
      }
      node.loading = true;
      this.treeRoots.update((r) => [...r]);
      this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType).subscribe({
        next: (children) => {
          node.children = children.map((c) => ({ ...c, level: (node.level ?? 0) + 1 }));
          node.loading = false;
          this.treeRoots.update((r) => [...r]);
        },
        error: () => {
          node.loading = false;
          node.children = [];
          this.treeRoots.update((r) => [...r]);
        },
      });
    }
  }

  isNodeSelected(node: TreeNode): boolean {
    return this.selectedNodes().some(
      (s) => s.nodeNs === node.nodeNs && String(s.nodeId) === String(node.nodeId)
    );
  }

  toggleNodeSelection(node: TreeNode): void {
    if (this.isNodeSelected(node)) {
      this.selectedNodes.update((sel) =>
        sel.filter((s) => !(s.nodeNs === node.nodeNs && String(s.nodeId) === String(node.nodeId)))
      );
    } else {
      this.selectedNodes.update((sel) => [
        ...sel,
        {
          displayName: node.displayName,
          nodeNs: node.nodeNs,
          nodeId: node.nodeId,
          nodeIdType: node.nodeIdType,
        },
      ]);
    }
  }

  removeSelectedNode(sel: SelectedNode): void {
    this.selectedNodes.update((arr) =>
      arr.filter((s) => !(s.nodeNs === sel.nodeNs && String(s.nodeId) === String(sel.nodeId)))
    );
  }

  getWizardNodeIcon(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder': return 'folder';
      case 'object': return 'inventory_2';
      case 'variable': return 'bar_chart';
      case 'property': return 'build';
      default: return 'circle';
    }
  }

  getWizardNodeIconClass(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder': return 'text-slate-500';
      case 'object': return 'text-amber-600';
      case 'variable': return 'text-blue-500';
      default: return 'text-slate-400';
    }
  }

  nextStep(): void {
    if (this.currentStep() < 3) {
      this.currentStep.update((s) => s + 1);
      this.stepProgress.set((this.currentStep() / 3) * 100);
    }
  }

  prevStep(): void {
    if (this.currentStep() > 0) {
      this.currentStep.update((s) => s - 1);
      this.stepProgress.set((this.currentStep() / 3) * 100);
    }
  }

  cancel(): void {
    this.router.navigate(['/pipelines']);
  }

  deploy(): void {
    this.deploying.set(true);
    this.deployError.set('');

    const fullClassName = this.packagePath
      ? `${this.packagePath}.${this.className}`
      : this.className;

    this.api
      .deploy({
        nodes: this.selectedNodes(),
        className: fullClassName,
        dataSourceName: this.dataSourceName,
        mode: this.pipelineMode,
      })
      .subscribe({
        next: (result) => {
          this.deploying.set(false);
          if (result.deployed) {
            this.deploySuccess.set(true);
            this.deployMessage.set(
              `Pipeline "${this.dataSourceName}" deployed successfully as ${result.dataSourceClass}.`
            );
          } else {
            this.deploySuccess.set(false);
            this.deployMessage.set(result.error || 'Deployment failed.');
          }
          this.nextStep();
        },
        error: (err) => {
          this.deploying.set(false);
          this.deployError.set(err.message || 'Deployment failed');
        },
      });
  }

  finish(): void {
    this.router.navigate(['/pipelines']);
  }
}
