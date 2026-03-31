import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import {
  TreeNode,
  OpcuaNode,
  SelectedNode,
  Pipeline,
  DeployV2Request,
  V2Selection,
  PipelineGroup,
  ColumnDef,
  RowSource,
} from '../../core/models/opcua.models';

@Component({
  selector: 'app-pipeline-wizard',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    @if (!isConfigured()) {
      <div class="flex items-center justify-center min-h-[calc(100vh-64px)]">
        <div class="text-center max-w-md px-8">
          <div class="w-24 h-24 mx-auto mb-8 rounded-2xl bg-surface-container-low flex items-center justify-center">
            <span class="material-symbols-outlined text-5xl text-on-surface-variant/30">hub</span>
          </div>
          <h2 class="text-2xl font-semibold text-on-surface mb-3 tracking-tight">Server Not Configured</h2>
          <p class="text-sm text-on-surface-variant leading-relaxed mb-8">
            You need to configure your OPC UA server connection before creating a pipeline. Set the server URL and test the connection in Settings.
          </p>
          <div class="flex items-center gap-3 justify-center">
            <button (click)="openSettings()"
                    class="px-6 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
              <span class="material-symbols-outlined text-sm">settings</span>
              Open Settings
            </button>
            <button (click)="cancel()"
                    class="px-6 py-3 bg-surface-container-high text-on-surface-variant font-semibold rounded-lg hover:bg-surface-variant transition-colors">
              Back
            </button>
          </div>
        </div>
      </div>
    } @else {
    <div class="p-8 max-w-7xl mx-auto w-full">
      <!-- Edit Mode Banner -->
      @if (editMode()) {
        <div class="mb-8 bg-amber-50 border border-amber-200 rounded-xl p-4 flex items-center gap-4 max-w-4xl mx-auto">
          <div class="w-10 h-10 rounded-lg bg-amber-100 flex items-center justify-center">
            <span class="material-symbols-outlined text-amber-700">edit_note</span>
          </div>
          <div class="flex-1">
            <p class="text-sm font-bold text-amber-900">Editing Pipeline: {{ editPipelineName() }}</p>
            <p class="text-xs text-amber-700">Modify the node selection below. The pipeline will be updated in place.</p>
          </div>
          <span class="px-3 py-1 bg-amber-200 text-amber-800 text-[10px] font-bold uppercase tracking-widest rounded-full">Edit Mode</span>
        </div>
      }

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

              <h1 class="text-2xl font-semibold text-on-surface mb-3 tracking-tight mt-8">
                {{ editMode() ? 'Modify Pipeline Nodes' : 'Select Data Nodes' }}
              </h1>
              <p class="text-on-surface-variant text-center max-w-md mb-10 text-sm leading-relaxed">
                Browse the OPC UA address space and select devices or individual sensors.
                Checking a device auto-selects all its child attributes as columns.
              </p>
              <!-- Edit mode warnings -->
              @if (editMode() && selectedNodes().length === 0) {
                <div class="mb-4 px-4 py-3 bg-error-container/20 border border-error/20 rounded-lg flex items-center gap-2 max-w-md">
                  <span class="material-symbols-outlined text-error text-sm">warning</span>
                  <span class="text-xs text-error font-medium">Pipeline must have at least one node selected.</span>
                </div>
              }
              @if (editHasNoOverlap()) {
                <div class="mb-4 px-4 py-3 bg-error-container/20 border border-error/20 rounded-lg max-w-md">
                  <div class="flex items-center gap-2 mb-2">
                    <span class="material-symbols-outlined text-error text-sm">block</span>
                    <span class="text-xs text-error font-bold">Nodes don't match this pipeline's schema</span>
                  </div>
                  <p class="text-[11px] text-error/80 mb-2">
                    <span class="font-semibold">{{ editNonMatchingColumns().join(', ') }}</span>
                    — these nodes share no columns with the existing pipeline. Remove them or create a separate pipeline.
                  </p>
                  <button (click)="createNewPipelineFromNonMatching()"
                          class="text-[11px] font-bold text-primary hover:underline flex items-center gap-1">
                    <span class="material-symbols-outlined text-xs">add_circle</span>
                    Create New Pipeline for these nodes
                  </button>
                </div>
              }
              @if (editHasNoChanges()) {
                <div class="mb-4 px-4 py-3 bg-surface-container border border-outline-variant/20 rounded-lg flex items-center gap-2 max-w-md">
                  <span class="material-symbols-outlined text-on-surface-variant text-sm">info</span>
                  <span class="text-xs text-on-surface-variant font-medium">No changes detected. Modify your selection to update the pipeline.</span>
                </div>
              }

              <div class="flex items-center gap-4">
                <button (click)="nextStep()"
                        [disabled]="selectedNodes().length === 0 || editHasNoOverlap() || editHasNoChanges()"
                        class="px-8 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all disabled:opacity-40 disabled:cursor-not-allowed">
                  {{ editMode() ? 'Review Changes' : 'Review Selection' }}
                  <span class="material-symbols-outlined">arrow_forward</span>
                </button>
                <button (click)="cancel()"
                        class="px-6 py-3 bg-surface-container-high text-on-surface-variant font-semibold rounded-lg hover:bg-surface-variant transition-colors">
                  Cancel
                </button>
              </div>

              <!-- Grouped selection preview -->
              @for (group of pipelineGroups(); track group.schemaKey) {
                <div class="mt-4 w-full max-w-lg bg-surface-container-low rounded-xl border border-outline-variant/10 overflow-hidden">
                  <!-- Group header -->
                  <div class="p-4 flex items-center gap-3">
                    <div class="w-10 h-10 rounded-lg flex items-center justify-center shadow-sm"
                         [class]="group.rowSources.length > 1 ? 'bg-primary text-on-primary' : 'bg-white text-primary'">
                      <span class="material-symbols-outlined">{{ group.rowSources.length > 1 ? 'device_hub' : 'inventory_2' }}</span>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">
                        {{ group.rowSources.length > 1 ? group.rowSources.length + ' Devices' : group.rowSources[0].displayName }}
                      </p>
                      <p class="text-xs text-on-surface-variant">
                        {{ group.columns.length }} column{{ group.columns.length !== 1 ? 's' : '' }}:
                        {{ columnNames(group) }}
                      </p>
                    </div>
                    <button (click)="removeGroup(group)"
                            class="material-symbols-outlined text-error cursor-pointer hover:bg-error-container/20 p-2 rounded-full transition-colors text-lg">
                      close
                    </button>
                  </div>
                  <!-- Row sources list -->
                  @if (group.rowSources.length > 1) {
                    <div class="px-4 pb-3 flex flex-wrap gap-1.5">
                      @for (rs of group.rowSources; track rs.nodeId) {
                        <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-surface-container-lowest rounded text-[11px] text-on-surface-variant">
                          {{ rs.displayName }}
                          <span class="material-symbols-outlined text-[12px] cursor-pointer hover:text-error transition-colors"
                                (click)="removeRowSource(group, rs)">close</span>
                        </span>
                      }
                    </div>
                  }
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

        <!-- STEP 2: REVIEW PIPELINE GROUPS -->
        @if (currentStep() === 1) {
          <div class="max-w-4xl mx-auto">
            <h1 class="text-2xl font-semibold text-on-surface mb-2 tracking-tight">Review Pipeline Structure</h1>
            <p class="text-on-surface-variant text-sm mb-8">
              @if (pipelineGroups().length > 1) {
                Your selection will create {{ pipelineGroups().length }} separate pipelines because the selected nodes have different schemas.
              } @else if (pipelineGroups().length === 1 && pipelineGroups()[0].rowSources.length > 1) {
                {{ pipelineGroups()[0].rowSources.length }} devices share the same schema and will be deployed as separate pipelines with identical structure.
              } @else {
                Review the pipeline structure below before configuring deployment settings.
              }
            </p>

            <div class="space-y-6 mb-8">
              @for (group of pipelineGroups(); track group.schemaKey; let gi = $index) {
                <div class="bg-surface-container-lowest rounded-xl border border-outline-variant/10 shadow-sm overflow-hidden">
                  <!-- Pipeline group header -->
                  <div class="p-6 border-b border-outline-variant/10">
                    <div class="flex items-center gap-3 mb-4">
                      <div class="w-10 h-10 rounded-lg bg-primary text-on-primary flex items-center justify-center">
                        <span class="material-symbols-outlined">{{ group.rowSources.length > 1 ? 'device_hub' : 'table_chart' }}</span>
                      </div>
                      <div>
                        @if (pipelineGroups().length > 1) {
                          <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Pipeline {{ gi + 1 }}</p>
                        }
                        <h3 class="text-base font-semibold text-on-surface">
                          {{ group.columns.length }} Column{{ group.columns.length !== 1 ? 's' : '' }}
                          @if (group.rowSources.length > 1) {
                            &times; {{ group.rowSources.length }} Row Source{{ group.rowSources.length !== 1 ? 's' : '' }}
                          }
                        </h3>
                      </div>
                    </div>

                    <!-- Column chips -->
                    <div class="flex flex-wrap gap-2">
                      <span class="px-3 py-1.5 bg-primary/10 text-primary rounded-lg text-xs font-bold">NodePath</span>
                      @for (col of group.columns; track col.displayName) {
                        <span class="px-3 py-1.5 bg-surface-container rounded-lg text-xs font-medium text-on-surface">{{ col.displayName }}</span>
                      }
                    </div>
                  </div>

                  <!-- Table preview -->
                  <div class="p-6">
                    <div class="overflow-x-auto">
                      <table class="w-full text-xs">
                        <thead>
                          <tr class="border-b border-outline-variant/20">
                            <th class="text-left py-2 px-3 font-bold text-primary text-[10px] uppercase tracking-widest">NodePath</th>
                            @for (col of group.columns; track col.displayName) {
                              <th class="text-left py-2 px-3 font-bold text-on-surface-variant text-[10px] uppercase tracking-widest">{{ col.displayName }}</th>
                            }
                          </tr>
                        </thead>
                        <tbody>
                          @for (rs of group.rowSources; track rs.nodeId) {
                            <tr class="border-b border-outline-variant/10 last:border-0">
                              <td class="py-2 px-3 font-mono text-on-surface-variant">{{ rs.path }}</td>
                              @for (col of group.columns; track col.displayName) {
                                <td class="py-2 px-3 text-on-surface-variant italic">--</td>
                              }
                            </tr>
                          }
                        </tbody>
                      </table>
                    </div>

                    <!-- Row sources detail -->
                    @if (group.rowSources.length > 1) {
                      <div class="mt-4 pt-4 border-t border-outline-variant/10">
                        <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-2">Row Sources (Devices)</p>
                        <div class="flex flex-wrap gap-2">
                          @for (rs of group.rowSources; track rs.nodeId) {
                            <span class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-surface-container rounded-lg text-xs">
                              <span class="material-symbols-outlined text-amber-600 text-sm">inventory_2</span>
                              {{ rs.displayName }}
                              <span class="text-on-surface-variant font-mono text-[10px]">{{ rs.path }}</span>
                            </span>
                          }
                        </div>
                      </div>
                    }
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
              <button (click)="onReviewContinue()"
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

              <!-- Pipeline configs -->
              @if (totalDeployUnits() === 1) {
                <!-- Single pipeline config -->
                <section class="bg-surface-container-lowest rounded-xl p-8 shadow-sm">
                  <div class="flex items-center gap-3 mb-6">
                    <span class="material-symbols-outlined text-primary">account_tree</span>
                    <h2 class="text-xl font-semibold tracking-tight">DataSource Class</h2>
                  </div>
                  <div class="space-y-6">
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                      <div class="space-y-1">
                        <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Package Path</label>
                        <input type="text" [(ngModel)]="packagePath" [disabled]="editMode()"
                               class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3 disabled:opacity-50"
                               placeholder="OPCUA.DS">
                      </div>
                      <div class="space-y-1">
                        <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Class Name</label>
                        <input type="text" [(ngModel)]="className" [disabled]="editMode()"
                               class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3 disabled:opacity-50"
                               placeholder="MyDataSource">
                      </div>
                    </div>
                    <div class="space-y-1">
                      <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Data Source Name</label>
                      <input type="text" [(ngModel)]="dataSourceName" [disabled]="editMode()"
                             class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3 disabled:opacity-50"
                             placeholder="Production_Line_1">
                    </div>
                  </div>
                </section>
              } @else {
                <!-- Multi-pipeline config -->
                <section class="bg-surface-container-lowest rounded-xl p-8 shadow-sm">
                  <div class="flex items-center gap-3 mb-6">
                    <span class="material-symbols-outlined text-primary">account_tree</span>
                    <h2 class="text-xl font-semibold tracking-tight">Pipeline Configuration</h2>
                  </div>
                  <p class="text-sm text-on-surface-variant mb-6">
                    {{ totalDeployUnits() }} pipeline{{ totalDeployUnits() !== 1 ? 's' : '' }} will be created (different schemas). Configure the shared package path and base names below.
                  </p>
                  <div class="space-y-6">
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                      <div class="space-y-1">
                        <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Package Path</label>
                        <input type="text" [(ngModel)]="packagePath"
                               class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3"
                               placeholder="OPCUA.DS">
                      </div>
                      <div class="space-y-1">
                        <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Base Class Name</label>
                        <input type="text" [(ngModel)]="className"
                               class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3"
                               placeholder="MyDataSource">
                      </div>
                    </div>
                    <div class="space-y-1">
                      <label class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Base Data Source Name</label>
                      <input type="text" [(ngModel)]="dataSourceName"
                             class="w-full bg-surface-container-lowest border-outline-variant/20 rounded-lg text-sm focus:ring-2 focus:ring-primary focus:border-transparent transition-all px-4 py-3"
                             placeholder="Production_Line">
                    </div>
                    <!-- Preview of generated names -->
                    <div class="bg-surface-container-low rounded-lg p-4">
                      <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-3">Generated Pipelines</p>
                      <div class="space-y-2">
                        @for (group of pipelineGroups(); track group.schemaKey; let gi = $index) {
                          <div class="flex items-center gap-3 text-xs">
                            <span class="material-symbols-outlined text-primary text-sm">subdirectory_arrow_right</span>
                            <span class="font-mono text-on-surface">{{ packagePath }}.{{ className }}{{ pipelineGroups().length > 1 ? '_' + groupSuffix(group) : '' }}</span>
                            <span class="text-on-surface-variant">&rarr;</span>
                            <span class="font-mono text-on-surface-variant">{{ group.columns.length }} cols &times; {{ group.rowSources.length }} device{{ group.rowSources.length !== 1 ? 's' : '' }}</span>
                          </div>
                        }
                      </div>
                    </div>
                  </div>
                </section>
              }

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
                    Start pipeline{{ totalDeployUnits() > 1 ? 's' : '' }} after deploy
                    <p class="text-xs text-on-surface-variant font-normal mt-1">Initialize telemetry stream immediately after successful configuration.</p>
                  </label>
                </div>
                <div class="space-y-3">
                  <button (click)="deploy()"
                          [disabled]="deploying() || !className || !dataSourceName"
                          class="w-full py-4 bg-gradient-to-br from-primary to-primary-container text-on-primary rounded-xl font-bold shadow-lg shadow-primary/20 active:scale-95 transition-all flex items-center justify-center gap-2 disabled:opacity-40">
                    @if (deploying()) {
                      {{ editMode() ? 'Updating' : 'Deploying' }}{{ totalDeployUnits() > 1 ? ' (' + deployProgress() + '/' + totalDeployUnits() + ')' : '' }}...
                    } @else {
                      {{ editMode() ? 'Update Pipeline' : totalDeployUnits() > 1 ? 'Deploy ' + totalDeployUnits() + ' Pipelines' : 'Deploy Pipeline' }}
                    }
                    <span class="material-symbols-outlined text-sm filled">{{ editMode() ? 'sync' : 'rocket_launch' }}</span>
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
            <h1 class="text-3xl font-semibold mb-4">{{ deploySuccess() ? editMode() ? 'Pipeline Updated' : 'Pipeline' + (deployResults().length > 1 ? 's' : '') + ' Deployed' : editMode() ? 'Update Failed' : 'Deployment Failed' }}</h1>
            <p class="text-on-surface-variant mb-8">{{ deployMessage() }}</p>

            <!-- Per-pipeline results (multi-pipeline) -->
            @if (deployResults().length > 1) {
              <div class="space-y-3 mb-8 text-left max-w-lg mx-auto">
                @for (r of deployResults(); track r.name) {
                  <div class="p-4 rounded-xl flex items-center gap-3 border"
                       [class]="r.success ? 'bg-tertiary-fixed/10 border-tertiary/20' : 'bg-error-container/10 border-error/20'">
                    <span class="material-symbols-outlined"
                          [class]="r.success ? 'text-tertiary' : 'text-error'">
                      {{ r.success ? 'check_circle' : 'error' }}
                    </span>
                    <div class="flex-1">
                      <p class="text-sm font-semibold text-on-surface">{{ r.name }}</p>
                      <p class="text-xs text-on-surface-variant">{{ r.message }}</p>
                    </div>
                  </div>
                }
              </div>
            }

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
             [class]="isNodeSelected(node) ? 'bg-primary/5 border-y border-primary/10' : isNodePartiallySelected(node) ? 'bg-primary/3' : 'hover:bg-white/50'"
             (click)="onWizardNodeClick(node)">
          <!-- Checkbox for selectable nodes (variables, objects, and folders) -->
          @if (node.nodeCategory === 'variable' || node.nodeCategory === 'object' || node.nodeCategory === 'folder') {
            <input type="checkbox" [checked]="isNodeSelected(node)"
                   [indeterminate]="isNodePartiallySelected(node)"
                   (click)="$event.stopPropagation()"
                   (change)="toggleNodeSelection(node)"
                   class="w-3.5 h-3.5 rounded border-slate-300 text-primary focus:ring-primary mr-1">
            @if (isAutoExpanding(node)) {
              <span class="material-symbols-outlined text-xs text-primary animate-spin -ml-1 mr-0.5">progress_activity</span>
            }
          }

          <!-- Expand arrow -->
          @if (node.hasChildren) {
            <span class="material-symbols-outlined text-lg"
                  [class]="isNodeSelected(node) || isNodePartiallySelected(node) ? 'text-primary' : 'text-slate-400'">
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
          <span class="text-sm" [class]="isNodeSelected(node) || isNodePartiallySelected(node) ? 'font-bold text-primary' : ''">
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
          @for (child of node.children; track wizardNodeKey(child) + ':' + $index) {
            <ng-container *ngTemplateOutlet="wizardTreeTpl; context: { $implicit: child, level: level + 1 }" />
          }
        }
      </div>
    </ng-template>
    }
  `,
})
export class PipelineWizardComponent {
  private api = inject(ApiService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  config = inject(ConfigService);

  isConfigured = computed(() => {
    const cfg = this.config.get();
    return !!(cfg.apiBaseUrl && cfg.serverUrl);
  });

  // Edit mode
  editMode = signal(false);
  editPipelineName = signal('');
  existingPipeline = signal<Pipeline | null>(null);
  existingClassName = signal('');

  steps = [
    { num: 1, label: 'Select' },
    { num: 2, label: 'Review' },
    { num: 3, label: 'Configure' },
    { num: 4, label: 'Deploy' },
  ];

  currentStep = signal(0);
  stepProgress = signal(0);

  // Step 1: Tree
  treeRoots = signal<TreeNode[]>([]);
  treeLoading = signal(false);
  searchQuery = '';

  // Primary selection state: Map<leafNodeKey, V2Selection>
  v2Selections = signal<Map<string, V2Selection>>(new Map());
  autoExpandingNodes = signal<Set<string>>(new Set());

  // Derived: flat list of selected leaf nodes (backward compat for template counts etc.)
  selectedNodes = computed(() =>
    Array.from(this.v2Selections().values()).map((s) => s.node)
  );

  // Derived: group selections by parent node
  parentGroups = computed(() => {
    const selections = this.v2Selections();
    const groups = new Map<string, { parent: V2Selection['parentNode']; children: V2Selection[] }>();
    for (const [, sel] of selections) {
      const parentKey = `${sel.parentNode.nodeNs}:${sel.parentNode.nodeId}`;
      if (!groups.has(parentKey)) {
        groups.set(parentKey, { parent: sel.parentNode, children: [] });
      }
      groups.get(parentKey)!.children.push(sel);
    }
    return groups;
  });

  // Derived: merge parents with overlapping columns into pipeline groups (union merge).
  // In CREATE mode: groups with overlapping columns merge; zero-overlap stays separate.
  // In EDIT mode: everything goes into ONE group (editing one pipeline).
  pipelineGroups = computed<PipelineGroup[]>(() => {
    const groups = this.parentGroups();

    // Build entries: one per parent group (using displayName as column key — original behavior)
    const entries: { columnNames: Set<string>; rowSource: RowSource }[] = [];
    for (const [, group] of groups) {
      entries.push({
        columnNames: new Set(group.children.map((c) => c.node.displayName)),
        rowSource: {
          displayName: group.parent.displayName,
          nodeNs: group.parent.nodeNs,
          nodeId: group.parent.nodeId,
          nodeIdType: group.parent.nodeIdType,
          path: group.parent.path,
          childNodes: group.children.map((c) => c.node),
        },
      });
    }

    let clusters: { columnNames: Set<string>; rowSources: RowSource[] }[];

    if (this.editMode()) {
      // Edit mode: force ALL entries into one group
      if (entries.length === 0) {
        clusters = [];
      } else {
        const allColumns = new Set<string>();
        const allRowSources: RowSource[] = [];
        for (const entry of entries) {
          entry.columnNames.forEach((c) => allColumns.add(c));
          allRowSources.push(entry.rowSource);
        }
        clusters = [{ columnNames: allColumns, rowSources: allRowSources }];
      }
    } else {
      // Create mode: connected-components merge (groups sharing any column name get merged)
      const used = new Set<number>();
      clusters = [];

      for (let i = 0; i < entries.length; i++) {
        if (used.has(i)) continue;
        used.add(i);

        const cluster = {
          columnNames: new Set(entries[i].columnNames),
          rowSources: [entries[i].rowSource],
        };

        let changed = true;
        while (changed) {
          changed = false;
          for (let j = 0; j < entries.length; j++) {
            if (used.has(j)) continue;
            const hasOverlap = [...entries[j].columnNames].some((c) => cluster.columnNames.has(c));
            if (hasOverlap) {
              used.add(j);
              entries[j].columnNames.forEach((c) => cluster.columnNames.add(c));
              cluster.rowSources.push(entries[j].rowSource);
              changed = true;
            }
          }
        }

        clusters.push(cluster);
      }
    }

    // Post-processing: merge nested clusters into their parent clusters.
    // If cluster B's row sources have paths that are children of cluster A's row sources,
    // absorb B into A and prefix B's columns with the intermediate path.
    // e.g., AC1/StateCondition/Quality merges into the AC1 cluster as "StateCondition/Quality"
    let mergedClusters = [...clusters];
    let mergeHappened = true;
    while (mergeHappened) {
      mergeHappened = false;
      for (let b = mergedClusters.length - 1; b >= 0; b--) {
        const childCluster = mergedClusters[b];
        for (let a = 0; a < mergedClusters.length; a++) {
          if (a === b) continue;
          const parentCluster = mergedClusters[a];

          // Check if ALL of childCluster's row sources are nested under some parentCluster row source
          let allNested = true;
          const matchMap: { childRS: RowSource; parentRS: RowSource; prefix: string }[] = [];
          for (const childRS of childCluster.rowSources) {
            let matched = false;
            for (const parentRS of parentCluster.rowSources) {
              if (childRS.path.startsWith(parentRS.path + '/')) {
                const suffix = childRS.path.slice(parentRS.path.length + 1);
                matchMap.push({ childRS, parentRS, prefix: suffix });
                matched = true;
                break;
              }
            }
            if (!matched) { allNested = false; break; }
          }

          if (allNested && matchMap.length > 0) {
            // Merge: transfer child's columns (prefixed) and childNodes to parent cluster
            for (const { childRS, parentRS, prefix } of matchMap) {
              for (const cn of childRS.childNodes) {
                const nestedPath = prefix + '/' + cn.displayName;
                parentCluster.columnNames.add(nestedPath);
                parentRS.childNodes = [
                  ...parentRS.childNodes,
                  { ...cn, relativePath: nestedPath.split('/') },
                ];
              }
            }
            // Remove the absorbed child cluster
            mergedClusters.splice(b, 1);
            mergeHappened = true;
            break;
          }
        }
        if (mergeHappened) break;
      }
    }

    // Auto-discover: for each row source, check its parent tree node's loaded children
    // for any union columns the user didn't explicitly select.
    const treeRoots = this.treeRoots();
    for (const cluster of mergedClusters) {
      for (const rs of cluster.rowSources) {
        const parentTreeNode = this.findTreeNode(treeRoots, rs.nodeNs, rs.nodeId);
        if (!parentTreeNode?.children) continue;

        const existingNames = new Set(rs.childNodes.map((c) => c.displayName));
        for (const colName of cluster.columnNames) {
          // Only auto-discover flat columns (not nested path-based ones)
          if (colName.includes('/')) continue;
          if (existingNames.has(colName)) continue;
          const child = parentTreeNode.children.find(
            (c) => c.displayName === colName && c.nodeCategory === 'variable'
          );
          if (child) {
            rs.childNodes = [
              ...rs.childNodes,
              { displayName: child.displayName, nodeNs: child.nodeNs, nodeId: child.nodeId, nodeIdType: child.nodeIdType },
            ];
          }
        }
      }
    }

    // Convert to PipelineGroup format
    return mergedClusters.map((cluster) => {
      const sortedColumns = [...cluster.columnNames].sort();
      return {
        schemaKey: sortedColumns.join('|'),
        columns: sortedColumns.map((name) => ({
          displayName: name,
          nodeCategory: 'variable',
          relativePath: name.split('/'),
        })),
        rowSources: cluster.rowSources,
      };
    });
  });

  // v2: one deploy per pipeline group (not per row source)
  totalDeployUnits = computed(() => this.pipelineGroups().length);

  // Edit mode validation

  // Columns from newly added nodes that have ZERO overlap with existing pipeline columns
  editNonMatchingColumns = computed<string[]>(() => {
    if (!this.editMode() || !this.existingPipeline()) return [];
    const existing = this.existingPipeline()!;
    const existingColNames = new Set(
      ((existing as any).nodes || []).map((n: any) => n.property || n.displayName)
    );
    if (existingColNames.size === 0) return [];

    // Check each parent group: if ALL its columns are outside the existing schema, it's non-matching
    const nonMatching: string[] = [];
    for (const [, group] of this.parentGroups()) {
      const childNames = group.children.map((c) => c.node.displayName);
      const hasOverlap = childNames.some((n) => existingColNames.has(n));
      if (!hasOverlap) {
        nonMatching.push(...childNames);
      }
    }
    return nonMatching;
  });

  editHasNoOverlap = computed(() => this.editNonMatchingColumns().length > 0);

  editHasNoChanges = computed(() => {
    if (!this.editMode() || !this.existingPipeline()) return false;
    const existing = this.existingPipeline()!;
    const existingColNames = ((existing as any).nodes || [])
      .map((n: any) => n.property || n.displayName).sort().join('|');
    const existingRSPaths = (existing.rowSources || [])
      .map((rs) => rs.path).sort().join('|');
    const groups = this.pipelineGroups();
    if (groups.length === 0) return true;
    const newColNames = groups[0].columns.map((c) => c.displayName).sort().join('|');
    const newRSPaths = groups[0].rowSources.map((rs) => rs.path).sort().join('|');
    return existingColNames === newColNames && existingRSPaths === newRSPaths;
  });

  // Step 3: Configure
  packagePath = 'OPCUA.DS';
  className = '';
  dataSourceName = '';
  pipelineMode: 'polling' | 'subscription' = 'polling';
  autoStart = true;

  // Step 4: Deploy
  deploying = signal(false);
  deployProgress = signal(0);
  deployError = signal('');
  deploySuccess = signal(false);
  deployMessage = signal('');
  deployResults = signal<{ name: string; success: boolean; message: string }[]>([]);

  constructor() {
    this.loadTree();

    // Detect edit mode from route params
    const name = this.route.snapshot.paramMap.get('name');
    if (name) {
      this.editMode.set(true);
      this.editPipelineName.set(name);
      this.loadExistingPipeline(name);
    }
  }

  private loadExistingPipeline(name: string): void {
    this.api.listPipelines().subscribe({
      next: (pipelines) => {
        const pipeline = pipelines.find((p) => p.name === name);
        if (!pipeline) return;

        this.existingPipeline.set(pipeline);
        this.existingClassName.set((pipeline as any).dataSourceClass || '');

        // Pre-fill configure fields
        const fullClass = (pipeline as any).dataSourceClass || '';
        const lastDot = fullClass.lastIndexOf('.');
        if (lastDot > 0) {
          this.packagePath = fullClass.substring(0, lastDot);
          this.className = fullClass.substring(lastDot + 1);
        } else {
          this.className = fullClass;
        }
        this.dataSourceName = pipeline.name;
        this.pipelineMode = (pipeline.mode as 'polling' | 'subscription') || 'polling';

        // Pre-populate v2Selections from pipeline's rowSources + childNodes
        if (pipeline.rowSources) {
          const selections = new Map<string, V2Selection>();
          for (const rs of pipeline.rowSources) {
            const parentInfo = {
              displayName: rs.path.split('/').pop() || rs.path,
              nodeNs: rs.nodeNs,
              nodeId: rs.nodeId,
              nodeIdType: rs.nodeIdType,
              path: rs.path,
            };
            for (const child of rs.childNodes || []) {
              const key = `${child.nodeNs}:${child.nodeId}`;
              const relativePath = child.relativePath || [child.displayName];
              selections.set(key, {
                node: {
                  displayName: child.displayName,
                  nodeNs: child.nodeNs,
                  nodeId: child.nodeId,
                  nodeIdType: child.nodeIdType,
                  path: `${rs.path}/${relativePath.join('/')}`,
                  relativePath,
                },
                parentNode: parentInfo,
              });
            }
          }
          this.v2Selections.set(selections);
        }
      },
    });
  }

  // --- Tree Loading ---

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

  private nodeKey(node: { nodeNs: number; nodeId: string | number }): string {
    return `${node.nodeNs}:${node.nodeId}`;
  }

  // --- Tree Interaction ---

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
          node.children = children.map((c) => ({
            ...c,
            level: (node.level ?? 0) + 1,
            parentRef: node,
          }));
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

  // --- Selection Logic ---

  isNodeSelected(node: TreeNode): boolean {
    if (node.nodeCategory === 'object' || node.nodeCategory === 'folder') {
      // Object is "selected" if all its variable children are selected
      if (!node.children || node.children.length === 0) return false;
      const variableChildren = node.children.filter((c) => c.nodeCategory === 'variable');
      if (variableChildren.length === 0) return false;
      const selections = this.v2Selections();
      return variableChildren.every((c) => selections.has(this.nodeKey(c)));
    }
    return this.v2Selections().has(this.nodeKey(node));
  }

  isNodePartiallySelected(node: TreeNode): boolean {
    if (node.nodeCategory !== 'object' && node.nodeCategory !== 'folder') return false;
    if (!node.children || node.children.length === 0) return false;
    const variableChildren = node.children.filter((c) => c.nodeCategory === 'variable');
    if (variableChildren.length === 0) return false;
    const selections = this.v2Selections();
    const selectedCount = variableChildren.filter((c) => selections.has(this.nodeKey(c))).length;
    return selectedCount > 0 && selectedCount < variableChildren.length;
  }

  isAutoExpanding(node: TreeNode): boolean {
    return this.autoExpandingNodes().has(this.nodeKey(node));
  }

  toggleNodeSelection(node: TreeNode): void {
    if (node.nodeCategory === 'object' || node.nodeCategory === 'folder') {
      // Object node: auto-expand and select/unselect all variable children
      if (this.isNodeSelected(node)) {
        this.unselectAllChildren(node);
      } else {
        if (node.children && node.children.length > 0) {
          this.selectAllVariableChildren(node);
          if (!node.expanded) {
            node.expanded = true;
            this.treeRoots.update((r) => [...r]);
          }
        } else {
          // Need to fetch children first
          const nk = this.nodeKey(node);
          this.autoExpandingNodes.update((s) => { const ns = new Set(s); ns.add(nk); return ns; });
          this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType).subscribe({
            next: (children) => {
              node.children = children.map((c) => ({
                ...c,
                level: (node.level ?? 0) + 1,
                parentRef: node,
              }));
              node.expanded = true;
              node.loading = false;
              // Guard: only auto-select if still in auto-expanding state
              if (this.autoExpandingNodes().has(nk)) {
                this.selectAllVariableChildren(node);
              }
              this.autoExpandingNodes.update((s) => { const ns = new Set(s); ns.delete(nk); return ns; });
              this.treeRoots.update((r) => [...r]);
            },
            error: () => {
              node.children = [];
              node.loading = false;
              this.autoExpandingNodes.update((s) => { const ns = new Set(s); ns.delete(nk); return ns; });
              this.treeRoots.update((r) => [...r]);
            },
          });
        }
      }
    } else if (node.nodeCategory === 'variable') {
      const key = this.nodeKey(node);
      if (this.v2Selections().has(key)) {
        this.v2Selections.update((m) => { const nm = new Map(m); nm.delete(key); return nm; });
      } else {
        const parentInfo = this.resolveParentInfo(node);
        this.v2Selections.update((m) => {
          const nm = new Map(m);
          nm.set(key, {
            node: {
              displayName: node.displayName,
              nodeNs: node.nodeNs,
              nodeId: node.nodeId,
              nodeIdType: node.nodeIdType,
              path: this.buildNodePath(node),
            },
            parentNode: parentInfo,
          });
          return nm;
        });
      }
    }
  }

  removeSelectedNode(sel: SelectedNode): void {
    const key = `${sel.nodeNs}:${sel.nodeId}`;
    this.v2Selections.update((m) => { const nm = new Map(m); nm.delete(key); return nm; });
  }

  removeGroup(group: PipelineGroup): void {
    this.v2Selections.update((m) => {
      const nm = new Map(m);
      for (const rs of group.rowSources) {
        for (const child of rs.childNodes) {
          nm.delete(`${child.nodeNs}:${child.nodeId}`);
        }
      }
      return nm;
    });
  }

  removeRowSource(group: PipelineGroup, rs: RowSource): void {
    this.v2Selections.update((m) => {
      const nm = new Map(m);
      for (const child of rs.childNodes) {
        nm.delete(`${child.nodeNs}:${child.nodeId}`);
      }
      return nm;
    });
  }

  // --- Selection Helpers ---

  private selectAllVariableChildren(parentNode: TreeNode): void {
    if (!parentNode.children) return;
    const parentInfo = {
      displayName: parentNode.displayName,
      nodeNs: parentNode.nodeNs,
      nodeId: parentNode.nodeId,
      nodeIdType: parentNode.nodeIdType,
      path: this.buildNodePath(parentNode),
    };

    this.v2Selections.update((m) => {
      const nm = new Map(m);
      for (const child of parentNode.children!) {
        if (child.nodeCategory === 'variable') {
          nm.set(this.nodeKey(child), {
            node: {
              displayName: child.displayName,
              nodeNs: child.nodeNs,
              nodeId: child.nodeId,
              nodeIdType: child.nodeIdType,
              path: this.buildNodePath(child),
            },
            parentNode: parentInfo,
          });
        }
      }
      return nm;
    });
  }

  private unselectAllChildren(parentNode: TreeNode): void {
    if (!parentNode.children) return;
    this.v2Selections.update((m) => {
      const nm = new Map(m);
      for (const child of parentNode.children!) {
        nm.delete(this.nodeKey(child));
      }
      return nm;
    });
  }

  private resolveParentInfo(node: TreeNode): V2Selection['parentNode'] {
    const parent = node.parentRef;
    if (parent) {
      return {
        displayName: parent.displayName,
        nodeNs: parent.nodeNs,
        nodeId: parent.nodeId,
        nodeIdType: parent.nodeIdType,
        path: this.buildNodePath(parent),
      };
    }
    // Fallback: the node sits directly under the root, use a synthetic root parent
    return {
      displayName: 'Objects',
      nodeNs: 0,
      nodeId: 85,
      nodeIdType: 0,
      path: 'Objects',
    };
  }

  private findTreeNode(roots: TreeNode[], nodeNs: number, nodeId: string | number): TreeNode | undefined {
    for (const node of roots) {
      if (node.nodeNs === nodeNs && String(node.nodeId) === String(nodeId)) return node;
      if (node.children) {
        const found = this.findTreeNode(node.children, nodeNs, nodeId);
        if (found) return found;
      }
    }
    return undefined;
  }

  buildNodePath(node: TreeNode): string {
    const parts: string[] = [];
    let current: TreeNode | undefined = node;
    while (current) {
      parts.unshift(current.displayName);
      current = current.parentRef;
    }
    return parts.join('/');
  }

  // --- Tree Icons ---

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

  // --- Step Navigation ---

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

  onReviewContinue(): void {
    // Auto-suggest names from the first row source if not already set
    if (!this.className && this.pipelineGroups().length > 0) {
      const firstGroup = this.pipelineGroups()[0];
      if (firstGroup.rowSources.length === 1 && this.totalDeployUnits() === 1) {
        this.className = this.sanitizeSuffix(firstGroup.rowSources[0].displayName);
        this.dataSourceName = this.className;
      }
    }
    this.nextStep();
  }

  cancel(): void {
    this.router.navigate(['/pipelines']);
  }

  openSettings(): void {
    document.dispatchEvent(new CustomEvent('open-settings'));
  }

  createNewPipelineFromNonMatching(): void {
    // Remove non-matching nodes from edit, then navigate to create with them
    // For now, just navigate to create — user can re-select there
    this.router.navigate(['/pipelines/new']);
  }

  // --- Deploy / Update (v2: one request per PipelineGroup) ---

  deploy(): void {
    this.deploying.set(true);
    this.deployError.set('');
    this.deployResults.set([]);

    const groups = this.pipelineGroups();
    if (groups.length === 0) return;

    // Edit mode: update existing pipeline
    if (this.editMode()) {
      const group = groups[0];
      const fullClassName = this.existingClassName();
      const payload = {
        ...this.buildV2Payload(group, fullClassName, this.dataSourceName),
        existingClassName: fullClassName,
      };

      this.api.editPipeline(payload).subscribe({
        next: (result: any) => {
          this.deploying.set(false);
          if (result.updated) {
            this.deploySuccess.set(true);
            this.deployMessage.set(
              `Pipeline "${this.dataSourceName}" updated successfully with ${group.rowSources.length} row source${group.rowSources.length !== 1 ? 's' : ''} and ${group.columns.length} column${group.columns.length !== 1 ? 's' : ''}.`
            );
            this.deployResults.set([{ name: this.dataSourceName, success: true, message: 'Updated successfully' }]);
          } else {
            this.deploySuccess.set(false);
            this.deployMessage.set(result.error || 'Update failed.');
            this.deployResults.set([{ name: this.dataSourceName, success: false, message: result.error || 'Failed' }]);
          }
          this.nextStep();
        },
        error: (err) => {
          this.deploying.set(false);
          this.deployError.set(err.message || 'Update failed');
        },
      });
      return;
    }

    // Create mode
    if (groups.length === 1) {
      // Single pipeline group -> single v2 deploy
      const group = groups[0];
      const fullClassName = this.packagePath
        ? `${this.packagePath}.${this.className}`
        : this.className;

      this.api
        .deploy(this.buildV2Payload(group, fullClassName, this.dataSourceName) as any)
        .subscribe({
          next: (result) => {
            this.deploying.set(false);
            if (result.deployed) {
              this.deploySuccess.set(true);
              this.deployMessage.set(
                `Pipeline "${this.dataSourceName}" deployed successfully as ${result.dataSourceClass} with ${group.rowSources.length} row source${group.rowSources.length !== 1 ? 's' : ''}.`
              );
              this.deployResults.set([{ name: this.dataSourceName, success: true, message: `Deployed as ${result.dataSourceClass}` }]);
            } else {
              this.deploySuccess.set(false);
              this.deployMessage.set(result.error || 'Deployment failed.');
              this.deployResults.set([{ name: this.dataSourceName, success: false, message: result.error || 'Failed' }]);
            }
            this.nextStep();
          },
          error: (err) => {
            this.deploying.set(false);
            this.deployError.set(err.message || 'Deployment failed');
          },
        });
    } else {
      // Multiple groups: deploy sequentially (one v2 request per group)
      this.deployProgress.set(0);
      this.deployGroupsSequential(groups, 0);
    }
  }

  private buildV2Payload(
    group: PipelineGroup,
    fullClassName: string,
    dataSourceName: string,
  ): DeployV2Request {
    return {
      className: fullClassName,
      dataSourceName,
      mode: this.pipelineMode,
      pipelineVersion: 2,
      columns: group.columns.map((c) => ({
        displayName: c.displayName,
        relativePath: c.relativePath || [c.displayName],
        inferredType: undefined, // backend will infer
      })),
      rowSources: group.rowSources.map((rs) => ({
        displayName: rs.displayName,
        nodeNs: rs.nodeNs,
        nodeId: rs.nodeId,
        nodeIdType: rs.nodeIdType,
        path: rs.path,
        childNodes: rs.childNodes.map((cn) => ({
          displayName: cn.displayName,
          nodeNs: cn.nodeNs,
          nodeId: cn.nodeId,
          nodeIdType: cn.nodeIdType,
          relativePath: cn.relativePath || [cn.displayName],
        })),
      })),
    };
  }

  private deployGroupsSequential(
    groups: PipelineGroup[],
    index: number,
  ): void {
    if (index >= groups.length) {
      this.deploying.set(false);
      const results = this.deployResults();
      const allSuccess = results.every((r) => r.success);
      const successCount = results.filter((r) => r.success).length;
      this.deploySuccess.set(allSuccess);
      this.deployMessage.set(
        allSuccess
          ? `All ${groups.length} pipelines deployed successfully.`
          : `${successCount} of ${groups.length} pipelines deployed successfully.`
      );
      this.nextStep();
      return;
    }

    const group = groups[index];
    const suffix = this.groupSuffix(group);
    const fullClassName = this.packagePath
      ? `${this.packagePath}.${this.className}_${suffix}`
      : `${this.className}_${suffix}`;
    const dsName = `${this.dataSourceName}_${suffix}`;

    this.deployProgress.set(index + 1);

    this.api
      .deploy(this.buildV2Payload(group, fullClassName, dsName) as any)
      .subscribe({
        next: (result) => {
          this.deployResults.update((r) => [
            ...r,
            {
              name: dsName,
              success: result.deployed,
              message: result.deployed
                ? `Deployed as ${result.dataSourceClass}`
                : result.error || 'Failed',
            },
          ]);
          this.deployGroupsSequential(groups, index + 1);
        },
        error: (err) => {
          this.deployResults.update((r) => [
            ...r,
            { name: dsName, success: false, message: err.message || 'Failed' },
          ]);
          this.deployGroupsSequential(groups, index + 1);
        },
      });
  }

  private sanitizeSuffix(name: string): string {
    return name.replace(/[^a-zA-Z0-9]/g, '');
  }

  groupSuffix(group: PipelineGroup): string {
    if (group.rowSources.length === 1) {
      return this.sanitizeSuffix(group.rowSources[0].displayName);
    }
    // Use the first column name as a distinguisher for multi-source groups
    return this.sanitizeSuffix(group.columns[0]?.displayName || 'Group');
  }

  finish(): void {
    this.router.navigate(['/pipelines']);
  }

  columnNames(group: PipelineGroup): string {
    return group.columns.map((c) => c.displayName).join(', ');
  }
}
