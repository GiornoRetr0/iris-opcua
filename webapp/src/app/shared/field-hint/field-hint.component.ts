import { Component } from '@angular/core';

/**
 * A small "i" beside a field label that reveals its explanation on hover.
 *
 * Takes projected content rather than a string input, because these hints carry
 * markup and conditionals — a monospaced default name, a `@if` that says something
 * different once the field is filled in — and flattening that to a plain string
 * would cost the copy its precision.
 *
 * Revealed on `group-hover` *and* `group-focus-within`: hover alone would hide the
 * text from anyone tabbing through the form, and this is where the non-obvious
 * facts live (which fields are permanent, what a category does).
 *
 * `pointer-events-none` on the bubble is deliberate — it is never interactive, and
 * without it the bubble can sit under the cursor and fight the hover it came from.
 */
@Component({
  selector: 'app-field-hint',
  standalone: true,
  template: `
    <span class="relative inline-flex items-center group align-middle">
      <button type="button"
              [attr.aria-label]="label"
              class="flex items-center justify-center h-4 w-4 rounded-full text-on-surface-muted
                     hover:text-primary hover:bg-primary-fixed/40 focus:outline-none
                     focus-visible:ring-2 focus-visible:ring-primary/40 transition-colors">
        <!-- Inline font-size: the Material Symbols stylesheet sets 24px on the class
             itself, which a Tailwind text-* utility does not reliably beat. -->
        <span class="material-symbols-outlined block" style="font-size:14px">info</span>
      </button>

      <span role="tooltip"
            class="pointer-events-none absolute left-1/2 -translate-x-1/2 top-full mt-2 z-30
                   w-60 rounded-lg bg-primary px-3 py-2 text-[11px] leading-relaxed text-on-primary
                   shadow-xl shadow-primary/20 opacity-0 invisible
                   group-hover:opacity-100 group-hover:visible
                   group-focus-within:opacity-100 group-focus-within:visible
                   transition-opacity duration-100">
        <ng-content />
      </span>
    </span>
  `,
})
export class FieldHintComponent {
  /**
   * Hardcoded rather than an input: every instance is the same affordance, and a
   * per-field label ("More information about Service name") would only add noise
   * for a screen reader that has just read the label this sits beside.
   */
  readonly label = 'More information';
}
