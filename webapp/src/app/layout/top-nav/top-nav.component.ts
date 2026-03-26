import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';

@Component({
  selector: 'app-top-nav',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  template: `
    <header class="bg-white/80 backdrop-blur-md shadow-sm sticky top-0 z-50">
      <div class="flex items-center justify-between px-6 py-3 w-full">
        <div class="flex items-center gap-8">
          <img src="intersystems-logo.png" alt="InterSystems" class="h-14" />
          <nav class="hidden md:flex gap-6">
            <a routerLink="/explorer" routerLinkActive="text-[#131c79] font-semibold border-b-2 border-[#131c79]"
               [routerLinkActiveOptions]="{exact: false}"
               class="text-slate-500 font-medium hover:text-[#131c79] transition-colors active:scale-95 duration-150">
              Node Explorer
            </a>
            <a routerLink="/pipelines" routerLinkActive="text-[#131c79] font-semibold border-b-2 border-[#131c79]"
               [routerLinkActiveOptions]="{exact: false}"
               class="text-slate-500 font-medium hover:text-[#131c79] transition-colors active:scale-95 duration-150">
              Pipelines
            </a>
          </nav>
        </div>
        <div class="flex items-center gap-4">
          <div class="hidden sm:flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold"
               [class]="apiOnline
                 ? 'bg-tertiary-fixed text-on-tertiary-fixed'
                 : 'bg-error-container text-on-error-container'">
            <span class="material-symbols-outlined text-[14px] filled">sensors</span>
            {{ apiOnline ? 'API Online' : 'API Offline' }}
          </div>
          <span class="material-symbols-outlined text-slate-500 hover:text-[#131c79] cursor-pointer"
                (click)="onSettingsClick()">settings</span>
        </div>
      </div>
      <div class="bg-slate-100 h-[1px] w-full"></div>
    </header>
  `,
})
export class TopNavComponent implements OnInit, OnDestroy {
  private api = inject(ApiService);
  private config = inject(ConfigService);

  apiOnline = false;
  private pingInterval: any;

  settingsOpen = false;

  ngOnInit(): void {
    this.checkApi();
    this.pingInterval = setInterval(() => this.checkApi(), 15000);
  }

  ngOnDestroy(): void {
    if (this.pingInterval) clearInterval(this.pingInterval);
  }

  private checkApi(): void {
    if (!this.config.get().apiBaseUrl) {
      this.apiOnline = false;
      return;
    }
    this.api.ping().subscribe({
      next: () => (this.apiOnline = true),
      error: () => (this.apiOnline = false),
    });
  }

  onSettingsClick(): void {
    // Emit event to parent shell via a simple approach
    document.dispatchEvent(new CustomEvent('open-settings'));
  }
}
