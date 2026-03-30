import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-side-nav',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  template: `
    <aside class="bg-slate-50 backdrop-blur-xl h-screen w-64 fixed left-0 top-0 pt-16 flex flex-col border-r border-slate-200/20 z-40">
      <!-- Branding -->
      <div class="p-6">
        <h2 class="text-lg font-bold text-[#131c79]">InterSystems</h2>
        <p class="text-[10px] uppercase tracking-widest text-on-surface-variant font-bold opacity-70">OPC UA Console</p>
      </div>

      <!-- Navigation -->
      <nav class="space-y-1 px-2 flex-grow overflow-y-auto custom-scrollbar">
        <a routerLink="/explorer"
           routerLinkActive="bg-blue-100/50 text-[#131c79]"
           [routerLinkActiveOptions]="{exact: false}"
           #explorerLink="routerLinkActive"
           class="rounded-lg flex items-center gap-3 px-3 py-2 cursor-pointer transition-all"
           [class]="explorerLink.isActive
             ? 'bg-blue-100/50 text-[#131c79]'
             : 'text-slate-600 hover:bg-slate-200/50'">
          <span class="material-symbols-outlined text-xl"
                [class.filled]="explorerLink.isActive">search</span>
          <span class="text-sm font-medium">Node Explorer</span>
        </a>

        <a routerLink="/pipelines"
           routerLinkActive="bg-blue-100/50 text-[#131c79]"
           [routerLinkActiveOptions]="{exact: false}"
           #pipelinesLink="routerLinkActive"
           class="rounded-lg flex items-center gap-3 px-3 py-2 cursor-pointer transition-all"
           [class]="pipelinesLink.isActive
             ? 'bg-blue-100/50 text-[#131c79]'
             : 'text-slate-600 hover:bg-slate-200/50'">
          <span class="material-symbols-outlined text-xl"
                [class.filled]="pipelinesLink.isActive">sync_alt</span>
          <span class="text-sm font-medium">Pipelines</span>
        </a>
      </nav>

      <!-- Footer -->
      <div class="p-4">
        <a routerLink="/pipelines/new"
           class="flex items-center gap-3 bg-primary text-on-primary px-4 py-2.5 rounded-full shadow-[0_20px_40px_rgba(19,28,121,0.25)] hover:shadow-[0_25px_50px_rgba(19,28,121,0.35)] transition-all transform active:scale-95 relative z-10">
          <span class="material-symbols-outlined bg-on-primary text-primary h-7 w-7 rounded-full text-center text-lg" style="line-height: 28px; vertical-align: unset">add</span>
          <span class="font-bold text-sm tracking-wide">Create New Pipeline</span>
        </a>
      </div>
    </aside>
  `,
})
export class SideNavComponent {
  openSettings(): void {
    document.dispatchEvent(new CustomEvent('open-settings'));
  }
}
