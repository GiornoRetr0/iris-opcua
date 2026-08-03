import { Component, input, output } from '@angular/core';
import { CommonModule } from '@angular/common';

/**
 * In-app confirmation for destructive actions.
 *
 * Replaces `window.confirm()`, which put browser chrome in the middle of an
 * otherwise fully custom UI — and, worse, rendered the carefully written
 * consequence copy as an unstyled wall of text with a literal blank line in it.
 * The copy was the good part; the vessel was wrong.
 *
 * `detail` is where the consequence goes — what survives, what does not. Say it
 * here rather than leaving the user to guess from the title.
 */
@Component({
  selector: 'app-confirm-dialog',
  standalone: true,
  imports: [CommonModule],
  template: `
    <!-- Escape is the keyboard equivalent of a backdrop click, so the dismiss
         gesture is not mouse-only. Bound on the host rather than the backdrop div
         so it works wherever focus happens to be. -->
    <div class="fixed inset-0 z-[110] flex items-center justify-center bg-[#2e3132]/40 backdrop-blur-sm p-4"
         (click)="onBackdrop($event)"
         (keydown.escape)="cancelled.emit()"
         tabindex="-1">
      <div class="bg-surface-container-lowest w-full max-w-md rounded-xl shadow-[0_20px_40px_rgba(25,28,29,0.12)] overflow-hidden"
           role="dialog" aria-modal="true" [attr.aria-label]="title()">
        <div class="p-6">
          <div class="flex items-start gap-3">
            <div class="p-2 rounded-lg shrink-0"
                 [class]="destructive() ? 'bg-error-container/40 text-error' : 'bg-primary/10 text-primary'">
              <span class="material-symbols-outlined">{{ destructive() ? 'delete' : 'help' }}</span>
            </div>
            <div class="min-w-0">
              <h2 class="text-base font-bold text-on-surface">{{ title() }}</h2>
              @if (detail()) {
                <p class="text-sm text-on-surface-variant mt-2 whitespace-pre-line">{{ detail() }}</p>
              }
            </div>
          </div>
        </div>
        <div class="px-6 py-4 bg-surface-container-low/50 border-t border-outline-variant/10 flex justify-end gap-3">
          <button type="button" (click)="cancelled.emit()"
                  class="px-5 py-2.5 text-on-surface-variant text-sm font-semibold rounded-lg hover:bg-surface-variant transition-all">
            {{ cancelLabel() }}
          </button>
          <button type="button" (click)="confirmed.emit()"
                  class="px-5 py-2.5 text-sm font-semibold rounded-lg shadow-lg transition-all hover:brightness-110 active:scale-[0.98]"
                  [class]="destructive()
                    ? 'bg-error text-on-error shadow-error/20'
                    : 'bg-primary text-on-primary shadow-primary/20'">
            {{ confirmLabel() }}
          </button>
        </div>
      </div>
    </div>
  `,
})
export class ConfirmDialogComponent {
  title = input.required<string>();
  /** The consequence: what is kept, what is lost. */
  detail = input('');
  confirmLabel = input('Delete');
  cancelLabel = input('Cancel');
  destructive = input(true);

  confirmed = output<void>();
  cancelled = output<void>();

  /**
   * Backdrop click cancels. Only when the backdrop itself was hit — otherwise a
   * click anywhere in the dialog would dismiss it.
   */
  onBackdrop(event: MouseEvent): void {
    if (event.target === event.currentTarget) this.cancelled.emit();
  }
}
