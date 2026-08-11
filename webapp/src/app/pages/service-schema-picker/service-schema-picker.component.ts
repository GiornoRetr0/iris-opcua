import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { Schema } from '../../core/models/opcua.models';

/**
 * Step one of creating a business service: pick the schema it will collect.
 *
 * A business service is a schema bound to devices, and the schema half is fixed
 * once deployed — so choosing it is genuinely the first decision, not a detail.
 * This screen exists because the dashboard's empty state used to dump people on
 * the Schemas *library* instead: a management page, with delete buttons and
 * column inspectors, where the one thing they came to do was buried in a card
 * action. Here every card is the choice.
 *
 * The card visual is deliberately the library's, minus its three action buttons:
 * recognising the same card carries over what the badges mean, while the whole
 * card being the target means there is exactly one thing to click.
 */
@Component({
  selector: 'app-service-schema-picker',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      <!-- Header -->
      <div class="mb-8">
        <button (click)="back()"
                class="text-xs font-bold uppercase tracking-widest text-on-surface-variant hover:text-primary transition-colors flex items-center gap-1 mb-3">
          <span class="material-symbols-outlined text-base">arrow_back</span>
          Business Services
        </button>
        <h1 class="text-3xl font-semibold text-primary tracking-tight">Create Business Service</h1>
        <p class="text-on-surface-variant mt-1">
          Pick the schema this service will collect. You'll choose its devices next.
        </p>
      </div>

      @if (error()) {
        <div class="mb-6 flex items-start gap-3 bg-error-container/40 border border-error/20 rounded-xl px-4 py-3">
          <span class="material-symbols-outlined text-error text-xl">error</span>
          <div class="flex-1">
            <p class="text-sm font-semibold text-on-error-container">{{ error() }}</p>
          </div>
          <button (click)="load()" class="text-xs font-bold uppercase tracking-wider text-on-error-container hover:underline">
            Retry
          </button>
        </div>
      }

      @if (loading()) {
        <div class="flex items-center justify-center py-20 text-on-surface-variant">
          <span class="material-symbols-outlined text-2xl animate-spin mr-3">progress_activity</span>
          Loading schemas...
        </div>
      }

      <!-- Nothing to pick. A business service cannot exist without a schema, so
           this dead end has to hand over the action that resolves it rather than
           just reporting the emptiness. -->
      @if (!loading() && !error() && schemas().length === 0) {
        <div class="flex flex-col items-center justify-center py-20 text-on-surface-variant">
          <span class="material-symbols-outlined text-8xl opacity-10 mb-4">schema</span>
          <h2 class="text-xl font-semibold text-primary mb-2">No Schemas To Choose From</h2>
          <p class="text-sm text-on-surface-muted mb-6 max-w-md text-center">
            A business service collects a schema, so there has to be one first. Build it
            from the node tree, then come back and bind devices to it.
          </p>
          <button (click)="createSchema()"
                  class="px-6 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
            <span class="material-symbols-outlined">add</span>
            Create Schema
          </button>
        </div>
      }

      <!-- Schema cards: the whole card is the button. -->
      <div class="space-y-4">
        @for (schema of schemas(); track schema.schemaClass) {
          <button type="button" (click)="choose(schema)"
                  class="w-full text-left bg-surface-container-lowest border border-outline-variant/10 rounded-xl shadow-sm p-6
                         hover:shadow-md hover:border-primary/40 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40
                         active:scale-[0.995] transition-all group">
            <div class="flex items-center justify-between gap-4">
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
                    <!-- Reuse is the point of a schema, so an already-bound one is a
                         normal choice here, not a warning. -->
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
              <span class="material-symbols-outlined text-on-surface-variant group-hover:text-primary group-hover:translate-x-0.5 transition-all shrink-0">
                arrow_forward
              </span>
            </div>
          </button>
        }
      </div>
    </div>
  `,
})
export class ServiceSchemaPickerComponent implements OnInit {
  private api = inject(ApiService);
  private router = inject(Router);

  schemas = signal<Schema[]>([]);
  loading = signal(false);
  error = signal('');

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set('');
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

  /** Picking a schema hands off to the binding screen, which does the deploy. */
  choose(schema: Schema): void {
    this.router.navigate(['/pipelines/bind', schema.schemaClass]);
  }

  createSchema(): void {
    this.router.navigate(['/schemas/new']);
  }

  back(): void {
    this.router.navigate(['/pipelines']);
  }

  private message(err: any): string {
    return err?.error?.error || err?.message || 'Could not load schemas';
  }
}
