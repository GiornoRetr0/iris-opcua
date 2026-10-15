import { Component, signal, inject, OnInit, OnDestroy } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { CommonModule } from '@angular/common';
import { TopNavComponent } from '../top-nav/top-nav.component';
import { SideNavComponent } from '../side-nav/side-nav.component';
import { SettingsModalComponent } from '../../shared/settings-modal/settings-modal.component';
import { ConfigService } from '../../core/services/config.service';

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
      <app-settings-modal [initialTab]="settingsTab()" (closed)="settingsOpen.set(false)" />
    }
  `,
})
export class AppShellComponent implements OnInit, OnDestroy {
  private config = inject(ConfigService);

  settingsOpen = signal(false);
  settingsTab = signal<'servers' | 'gateway'>('servers');

  private handler = () => {
    this.settingsTab.set('servers');
    this.settingsOpen.set(true);
  };

  ngOnInit(): void {
    document.addEventListener('open-settings', this.handler);
    // A hosted console has no default account: ask for one before anything calls the API.
    if (this.config.hosted && !this.config.get().apiUsername) {
      this.settingsTab.set('gateway');
      this.settingsOpen.set(true);
    }
  }

  ngOnDestroy(): void {
    document.removeEventListener('open-settings', this.handler);
  }
}
