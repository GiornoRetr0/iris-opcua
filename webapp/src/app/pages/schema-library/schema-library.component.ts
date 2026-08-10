import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { Schema } from '../../core/models/opcua.models';
import { ConfirmDialogComponent } from '../../shared/confirm-dialog/confirm-dialog.component';

/**
 * Schema library: browse, inspect and delete reusable device schemas.
 *
 * A schema is a device *type* — its columns and the OPC UA node names they
 * resolve against — with no device binding. This page exists because that is now
 * a first-class artifact you can create, keep and reuse without any business service.
 */
@Component({
  selector: 'app-schema-library',
  standalone: true,
  imports: [CommonModule, ConfirmDialogComponent],
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      <!-- Page header -->
      <div class="flex justify-between items-end mb-10">
        <div class="space-y-1">
          <h1 class="text-3xl font-semibold text-primary tracking-tight">Schemas</h1>
          <p class="text-on-surface-variant">
            Reusable device types. Define the columns once, bind any number of devices to them.
          </p>
        </div>
        <button (click)="createSchema()"
                class="px-5 py-2.5 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/25 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
          <span class="material-symbols-outlined text-xl">add</span>
          <span class="text-sm tracking-wide">New Schema</span>
        </button>
      </div>

      <!-- Summary tiles -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-slate-300/40 group-hover:text-slate-300/60 transition-colors" style="font-size:80px">schema</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">Total Schemas</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-primary">{{ schemas().length }}</span>
              <span class="text-sm font-bold text-on-surface-muted">Defined</span>
            </div>
          </div>
        </div>
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-emerald-400/30 group-hover:text-emerald-400/50 transition-colors" style="font-size:80px">link</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">In Use</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-emerald-600">{{ inUseCount() }}</span>
              <span class="text-sm font-bold text-on-surface-muted">Bound</span>
            </div>
          </div>
        </div>
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-primary/20 group-hover:text-primary/35 transition-colors" style="font-size:80px">inventory_2</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">Unused</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-primary">{{ schemas().length - inUseCount() }}</span>
              <span class="text-sm font-bold text-on-surface-muted">Available</span>
            </div>
          </div>
        </div>
      </div>

      @if (error()) {
        <div class="mb-6 flex items-start gap-3 bg-error-container/40 border border-error/20 rounded-xl px-4 py-3">
          <span class="material-symbols-outlined text-error text-xl">error</span>
          <div class="flex-1">
            <p class="text-sm font-semibold text-on-error-container">{{ error() }}</p>
          </div>
          <button (click)="error.set('')" class="text-on-error-container/60 hover:text-on-error-container">
            <span class="material-symbols-outlined text-lg">close</span>
          </button>
        </div>
      }

      @if (loading()) {
        <div class="flex items-center justify-center py-20 text-on-surface-variant">
          <span class="material-symbols-outlined text-2xl animate-spin mr-3">progress_activity</span>
          Loading schemas...
        </div>
      }

      @if (!loading() && schemas().length === 0) {
        <div class="flex flex-col items-center justify-center py-20 text-on-surface-variant">
          <span class="material-symbols-outlined text-8xl opacity-10 mb-4">schema</span>
          <h2 class="text-xl font-semibold text-primary mb-2">No Schemas Yet</h2>
          <p class="text-sm text-on-surface-muted mb-6 max-w-md text-center">
            A schema describes one device type. Create one from the node tree, then bind as many
            identical devices to it as you like.
          </p>
          <button (click)="createSchema()"
                  class="px-6 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
            <span class="material-symbols-outlined">add</span>
            Create Schema
          </button>
        </div>
      }

      <!-- Schema cards -->
      <div class="space-y-4">
        @for (schema of schemas(); track schema.schemaClass) {
          <div class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl shadow-sm hover:shadow-md transition-shadow overflow-hidden">
            <div class="p-6">
              <div class="flex items-start justify-between">
                <div class="flex items-start gap-4 min-w-0">
                  <div class="h-12 w-12 rounded-lg flex items-center justify-center shrink-0"
                       [class]="schema.usedBy.length ? 'bg-tertiary-fixed/20 text-tertiary' : 'bg-surface-container-highest text-on-surface-variant'">
                    <span class="material-symbols-outlined text-2xl">schema</span>
                  </div>
                  <div class="min-w-0">
                    <h3 class="text-lg font-semibold text-primary truncate">{{ schema.name }}</h3>
                    <p class="text-[11px] font-mono text-on-surface-variant truncate">{{ schema.schemaClass }}</p>
                    <div class="flex items-center gap-3 mt-2 flex-wrap">
                      <span class="inline-flex items-center gap-1 text-xs text-on-surface-variant">
                        <span class="material-symbols-outlined text-sm">view_column</span>
                        {{ schema.columnCount }} column{{ schema.columnCount === 1 ? '' : 's' }}
                      </span>
                      <span class="inline-flex items-center gap-1 text-xs text-on-surface-variant">
                        <span class="material-symbols-outlined text-sm">table</span>
                        <span class="font-mono">{{ schema.tableName }}</span>
                      </span>
                      @if (schema.usedBy.length) {
                        <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-tertiary-fixed/25 text-[10px] font-bold uppercase tracking-wider text-tertiary">
                          <span class="material-symbols-outlined text-[12px]">link</span>
                          {{ schema.usedBy.length }} service{{ schema.usedBy.length === 1 ? '' : 's' }}
                        </span>
                      } @else {
                        <span class="px-2 py-0.5 rounded-full bg-surface-container-highest text-[10px] font-bold uppercase tracking-wider text-on-surface-variant">
                          Unused
                        </span>
                      }
                    </div>
                  </div>
                </div>

                <div class="flex items-center gap-2 shrink-0">
                  <button (click)="bindDevices(schema)"
                          title="Create a business service from this schema"
                          class="px-3 py-2 rounded-lg text-xs font-bold uppercase tracking-wider text-primary hover:bg-primary-fixed/30 transition-colors flex items-center gap-1.5">
                    <span class="material-symbols-outlined text-lg">device_hub</span>
                    Bind Devices
                  </button>
                  <button (click)="toggleDetail(schema)"
                          [title]="expanded() === schema.schemaClass ? 'Hide columns' : 'Show columns'"
                          class="p-2 text-on-surface-variant hover:text-primary transition-colors rounded-lg hover:bg-primary-fixed/20">
                    <span class="material-symbols-outlined transition-transform"
                          [class.rotate-180]="expanded() === schema.schemaClass">expand_more</span>
                  </button>
                  <button (click)="remove(schema)"
                          [disabled]="schema.usedBy.length > 0"
                          [title]="schema.usedBy.length
                            ? 'In use by: ' + schema.usedBy.join(', ')
                            : 'Delete this schema'"
                          class="p-2 rounded-lg transition-colors"
                          [class]="schema.usedBy.length
                            ? 'text-on-surface-variant/30 cursor-not-allowed'
                            : 'text-on-surface-variant hover:text-error hover:bg-error-container/20'">
                    <span class="material-symbols-outlined">delete</span>
                  </button>
                </div>
              </div>

              @if (schema.usedBy.length) {
                <div class="mt-4 pt-4 border-t border-outline-variant/10 flex items-center gap-2 flex-wrap">
                  <span class="text-[0.6rem] font-bold text-on-surface-variant uppercase tracking-widest">Used by</span>
                  @for (name of schema.usedBy; track name) {
                    <span class="px-2 py-1 rounded-md bg-surface-container text-xs font-medium text-primary">{{ name }}</span>
                  }
                </div>
              }
            </div>

            <!-- Column detail -->
            @if (expanded() === schema.schemaClass) {
              <div class="border-t border-outline-variant/10 bg-surface-container-low/40 px-6 py-5">
                @if (detailLoading()) {
                  <div class="flex items-center gap-2 text-on-surface-variant text-sm">
                    <span class="material-symbols-outlined text-lg animate-spin">progress_activity</span>
                    Loading columns...
                  </div>
                } @else {
                  <div class="text-[0.6rem] font-bold text-on-surface-variant uppercase tracking-widest mb-3">
                    Columns — matched by name against each device
                  </div>
                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                    @for (col of detailColumns(); track col.propertyPath) {
                      <div class="flex items-center gap-2 bg-surface-container-lowest border border-outline-variant/10 rounded-lg px-3 py-2">
                        <span class="material-symbols-outlined text-sm shrink-0"
                              [class]="col.folder ? 'text-amber-600' : 'text-tertiary'">
                          {{ col.folder ? 'folder_open' : 'label' }}
                        </span>
                        <div class="min-w-0">
                          <p class="text-xs font-semibold text-on-surface truncate">
                            @if (col.folder) {
                              <span class="text-on-surface-variant">{{ col.folder }}/</span>
                            }{{ col.nodeName }}
                          </p>
                          <p class="text-[10px] text-on-surface-variant">ns={{ col.namespace }}</p>
                        </div>
                      </div>
                    }
                  </div>
                }
              </div>
            }
          </div>
        }
      </div>
    </div>

    @if (pendingDelete()) {
      <app-confirm-dialog
        [title]="'Delete schema &quot;' + pendingDelete()!.name + '&quot;?'"
        [detail]="deleteDetail()"
        confirmLabel="Delete schema and table"
        (confirmed)="confirmDelete()"
        (cancelled)="pendingDelete.set(null)" />
    }
  `,
})
export class SchemaLibraryComponent implements OnInit {
  private api = inject(ApiService);
  private router = inject(Router);

  schemas = signal<Schema[]>([]);
  loading = signal(false);
  error = signal('');

  expanded = signal<string>('');
  detail = signal<Schema | null>(null);
  detailLoading = signal(false);

  inUseCount = computed(() => this.schemas().filter((s) => s.usedBy.length > 0).length);

  detailColumns = computed(() => this.detail()?.columns ?? []);

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.api.listSchemas().subscribe({
      next: (schemas) => {
        this.schemas.set(schemas);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.schemas.set([]);
        this.loading.set(false);
      },
    });
  }

  toggleDetail(schema: Schema): void {
    if (this.expanded() === schema.schemaClass) {
      this.expanded.set('');
      this.detail.set(null);
      return;
    }
    this.expanded.set(schema.schemaClass);
    this.detail.set(null);
    this.detailLoading.set(true);
    this.api.getSchema(schema.schemaClass).subscribe({
      next: (d) => {
        this.detail.set(d);
        this.detailLoading.set(false);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.detailLoading.set(false);
        this.expanded.set('');
      },
    });
  }

  createSchema(): void {
    this.router.navigate(['/schemas/new']);
  }

  /** Bind devices to an existing schema — the reuse flow. */
  bindDevices(schema: Schema): void {
    this.router.navigate(['/pipelines/bind', schema.schemaClass]);
  }

  /** Which schema the confirmation dialog is about, or null when it is closed. */
  pendingDelete = signal<Schema | null>(null);

  remove(schema: Schema): void {
    if (schema.usedBy.length) return;
    this.pendingDelete.set(schema);
  }

  /**
   * Deleting a schema *is* the data-losing operation — unlike deleting a business service,
   * which keeps both. Name the table, since that is what goes.
   */
  deleteDetail(): string {
    const s = this.pendingDelete();
    if (!s) return '';
    return `This drops the ${s.tableName} table and every row collected into it. ` +
      `Schema columns cannot be edited, so recreating it is the only way back — and the data does not come with it.`;
  }

  confirmDelete(): void {
    const schema = this.pendingDelete();
    if (!schema) return;
    this.pendingDelete.set(null);
    this.api.deleteSchema(schema.schemaClass).subscribe({
      next: () => this.load(),
      error: (err) => this.error.set(this.message(err)),
    });
  }

  private message(err: any): string {
    return err?.error?.error || err?.message || 'Request failed';
  }
}
