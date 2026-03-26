import { Component, signal, OnInit, OnDestroy } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { CommonModule } from '@angular/common';
import { TopNavComponent } from '../top-nav/top-nav.component';
import { SideNavComponent } from '../side-nav/side-nav.component';
import { SettingsModalComponent } from '../../shared/settings-modal/settings-modal.component';

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
      <app-settings-modal (closed)="settingsOpen.set(false)" />
    }
  `,
})
export class AppShellComponent implements OnInit, OnDestroy {
  settingsOpen = signal(false);

  private handler = () => this.settingsOpen.set(true);

  ngOnInit(): void {
    document.addEventListener('open-settings', this.handler);
  }

  ngOnDestroy(): void {
    document.removeEventListener('open-settings', this.handler);
  }
}
