import { Component, signal, inject, OnInit, OnDestroy } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { CommonModule } from '@angular/common';
import { TopNavComponent } from '../top-nav/top-nav.component';
import { SideNavComponent } from '../side-nav/side-nav.component';
import { SettingsModalComponent } from '../../shared/settings-modal/settings-modal.component';
import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [CommonModule, RouterOutlet, TopNavComponent, SideNavComponent, SettingsModalComponent],
  template: `
    <app-top-nav />
    <div class="flex min-h-screen">
      <app-side-nav />
      <main class="ml-64 flex-grow bg-surface-container-low min-h-screen">
        <router-outlet />
      </main>
    </div>
    @if (settingsOpen()) {
      <app-settings-modal [initialTab]="settingsTab()" [notice]="settingsNotice()" (closed)="closeSettings()" />
    }
  `,
})
export class AppShellComponent implements OnInit, OnDestroy {
  private auth = inject(AuthService);

  settingsOpen = signal(false);
  settingsTab = signal<'servers' | 'gateway'>('servers');

  /** Why Settings opened by itself, e.g. "Sign-in failed"; shown in the modal. */
  settingsNotice = signal('');

  /**
   * Who was signed in (or "" for nobody) when the user closed a sign-in notice.
   * Background calls (the API ping, the dashboard refresh) keep failing until the
   * user signs in, and must not reopen Settings every few seconds meanwhile.
   */
  private dismissedAccount: string | null = null;

  private handler = (event: Event) => {
    const detail = (event as CustomEvent).detail as { tab?: 'servers' | 'gateway'; notice?: string } | undefined;
    if (!detail?.notice) {
      this.settingsNotice.set('');
      this.settingsTab.set('servers');
      this.settingsOpen.set(true);
      return;
    }
    this.settingsNotice.set(detail.notice);
    // Already open: show the notice, but don't move the user off the tab they are on.
    if (this.settingsOpen()) return;
    if (this.dismissedAccount === this.account()) return;
    this.settingsTab.set(detail.tab ?? 'gateway');
    this.settingsOpen.set(true);
  };

  closeSettings(): void {
    this.dismissedAccount = this.settingsNotice() ? this.account() : null;
    this.settingsNotice.set('');
    this.settingsOpen.set(false);
  }

  private account(): string {
    return this.auth.user() ?? '';
  }

  ngOnInit(): void {
    document.addEventListener('open-settings', this.handler);
    // No session (a new tab of the hosted console, or the development login failed):
    // ask for a sign-in before anything calls the API.
    this.auth.ready.then(() => {
      if (!this.auth.user() && !this.settingsOpen()) {
        this.settingsTab.set('gateway');
        this.settingsOpen.set(true);
      }
    });
  }

  ngOnDestroy(): void {
    document.removeEventListener('open-settings', this.handler);
  }
}
