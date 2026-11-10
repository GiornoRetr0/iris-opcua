import { TestBed } from '@angular/core/testing';
import { ConfirmDialogComponent } from './confirm-dialog.component';

describe('ConfirmDialogComponent', () => {
  function icon(inputs: Record<string, unknown>): string {
    const f = TestBed.createComponent(ConfirmDialogComponent);
    f.componentRef.setInput('title', 'T');
    for (const [k, v] of Object.entries(inputs)) f.componentRef.setInput(k, v);
    f.detectChanges();
    return (f.nativeElement as HTMLElement).querySelector('.material-symbols-outlined')!.textContent!.trim();
  }

  it('shows a bin when destructive and a question mark otherwise, by default', () => {
    expect(icon({})).toBe('delete');
    expect(icon({ destructive: false })).toBe('help');
  });

  it('shows the icon it is given even when destructive', () => {
    expect(icon({ icon: 'key' })).toBe('key');
  });
});
