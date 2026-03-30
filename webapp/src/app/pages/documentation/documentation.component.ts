import { Component, signal, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-documentation',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="p-4 md:p-10 lg:p-16">
      <div class="max-w-5xl mx-auto flex flex-col lg:flex-row gap-12">
        <!-- Content Column -->
        <article class="flex-1 min-w-0">
          <!-- Breadcrumbs -->
          <nav class="flex items-center space-x-2 text-[10px] font-medium uppercase tracking-widest text-on-surface-variant/60 mb-8">
            <a class="hover:text-primary transition-colors cursor-pointer">Home</a>
            <span class="material-symbols-outlined text-[12px]">chevron_right</span>
            <span class="text-on-surface">Documentation</span>
          </nav>

          <h1 class="text-4xl md:text-5xl font-bold tracking-tight text-blue-950 mb-6">OPC UA Console Guide</h1>
          <p class="text-lg text-on-surface-variant leading-relaxed mb-12">
            Learn how to connect to OPC UA servers, browse industrial address spaces, deploy data collection
            pipelines, and monitor real-time telemetry from your devices.
          </p>

          <!-- Architecture Overview Section -->
          <section class="mb-16 bg-surface-container-low p-8 rounded-xl relative overflow-hidden">
            <div class="relative z-10 grid grid-cols-1 md:grid-cols-2 gap-8 items-center">
              <div>
                <h2 class="text-xl font-semibold mb-4 text-blue-900">How It Works</h2>
                <p class="text-sm text-on-surface-variant leading-relaxed">
                  The console connects to any OPC UA server, lets you browse its address space,
                  select nodes of interest, and deploy pipelines that continuously poll or subscribe
                  to data — storing it in IRIS tables for analytics and monitoring.
                </p>
              </div>
              <div class="h-48 rounded-lg bg-surface-container-lowest shadow-sm flex items-center justify-center p-4 border border-outline-variant/10">
                <div class="relative w-full h-full flex items-center justify-center">
                  <div class="w-12 h-12 bg-primary rounded-lg flex items-center justify-center text-white z-10">
                    <span class="material-symbols-outlined">hub</span>
                  </div>
                  <div class="absolute w-24 h-px bg-primary/20 -translate-x-16"></div>
                  <div class="absolute w-24 h-px bg-primary/20 translate-x-16"></div>
                  <div class="absolute w-16 h-16 border-2 border-dashed border-primary/20 rounded-full animate-pulse"></div>
                  <div class="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 bg-tertiary-fixed rounded-full shadow-lg"></div>
                  <div class="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 bg-primary-fixed rounded-full shadow-lg"></div>
                </div>
              </div>
            </div>
            <div class="absolute -right-16 -bottom-16 w-64 h-64 bg-primary/5 rounded-full blur-3xl"></div>
          </section>

          <!-- Getting Started -->
          <section class="mb-16" id="getting-started">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 1</span>
              <h2 class="text-2xl font-bold text-on-surface">Getting Started</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              Before browsing nodes or creating pipelines, configure your connection to an OPC UA server.
            </p>
            <div class="bg-[#1e1e1e] rounded-xl p-6 shadow-2xl relative group overflow-hidden mb-8">
              <div class="flex justify-between items-center mb-4">
                <span class="text-[10px] text-slate-500 font-mono tracking-widest uppercase">Configuration Steps</span>
              </div>
              <pre class="font-mono text-sm leading-6 text-slate-300"><code>1. Click <span class="text-blue-400">Settings</span> in the sidebar
2. Enter your OPC UA Server URL
   e.g. <span class="text-green-400">opc.tcp://your-server:4840</span>
3. Choose Security Mode (None or Sign & Encrypt)
4. If using certificates, fill in the Certificates tab
5. Click <span class="text-blue-400">Test Connection</span> to verify
6. Click <span class="text-blue-400">Save Changes</span></code></pre>
              <div class="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-primary/10 to-transparent pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"></div>
            </div>

            <!-- Settings Table -->
            <h3 class="text-lg font-bold text-on-surface mb-6">Connection Settings</h3>
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="border-b border-outline-variant/20">
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Setting</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Required</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Description</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Server URL</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">YES</span></td>
                    <td class="py-4 text-on-surface-variant">OPC UA endpoint (e.g., opc.tcp://plc:4840)</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Security Mode</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">YES</span></td>
                    <td class="py-4 text-on-surface-variant">None (unencrypted) or Sign & Encrypt (mutual TLS)</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">API Base URL</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">YES</span></td>
                    <td class="py-4 text-on-surface-variant">REST API endpoint for the IRIS backend</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Certificates</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">IF SECURE</span></td>
                    <td class="py-4 text-on-surface-variant">Client cert, private key, trust list, and CRL for Sign & Encrypt mode</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Node Explorer -->
          <section class="mb-16" id="node-explorer">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 2</span>
              <h2 class="text-2xl font-bold text-on-surface">Node Explorer</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              The Node Explorer lets you browse the OPC UA server's address space as a hierarchical tree.
              Click any node to expand it, and select variable nodes to read their current values.
            </p>
            <div class="bg-[#1e1e1e] rounded-xl p-6 shadow-2xl relative group overflow-hidden mb-8">
              <div class="flex justify-between items-center mb-4">
                <span class="text-[10px] text-slate-500 font-mono tracking-widest uppercase">Node Categories</span>
              </div>
              <pre class="font-mono text-sm leading-6 text-slate-300"><code><span class="text-slate-500">// Folder</span>    — Organizes nodes into groups
<span class="text-slate-500">// Object</span>    — A device or logical container (e.g., AC1)
<span class="text-slate-500">// Variable</span>  — A readable data point (e.g., Temperature)
<span class="text-slate-500">// Property</span>  — Metadata about a node

<span class="text-blue-400">Objects</span>
  <span class="text-amber-400">AirConditioner_1</span>        <span class="text-slate-500">← Object (device)</span>
    <span class="text-green-400">Temperature</span>           <span class="text-slate-500">← Variable (22.5)</span>
    <span class="text-green-400">Humidity</span>              <span class="text-slate-500">← Variable (45)</span>
    <span class="text-green-400">PowerConsumption</span>      <span class="text-slate-500">← Variable (1200)</span></code></pre>
              <div class="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-primary/10 to-transparent pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"></div>
            </div>

            <h3 class="text-lg font-bold text-on-surface mb-6">Features</h3>
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="border-b border-outline-variant/20">
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Feature</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Description</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Live Read</td>
                    <td class="py-4 text-on-surface-variant">Click any variable node to read its current value, timestamps, and status</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Auto-Refresh</td>
                    <td class="py-4 text-on-surface-variant">Enable automatic polling at a configurable interval (1-60 seconds)</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Telemetry Chart</td>
                    <td class="py-4 text-on-surface-variant">Visual bar chart showing the last 10 values for trend analysis</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Creating Pipelines -->
          <section class="mb-16" id="creating-pipelines">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 3</span>
              <h2 class="text-2xl font-bold text-on-surface">Creating Pipelines</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              Pipelines continuously collect data from OPC UA nodes and store it in IRIS tables.
              Use the 4-step wizard to select nodes, review the schema, configure settings, and deploy.
            </p>
            <div class="bg-[#1e1e1e] rounded-xl p-6 shadow-2xl relative group overflow-hidden mb-8">
              <div class="flex justify-between items-center mb-4">
                <span class="text-[10px] text-slate-500 font-mono tracking-widest uppercase">Wizard Steps</span>
              </div>
              <pre class="font-mono text-sm leading-6 text-slate-300"><code><span class="text-blue-400">Step 1: Select</span>    Browse the tree, check devices or sensors
<span class="text-blue-400">Step 2: Review</span>    See how nodes are grouped into pipelines
<span class="text-blue-400">Step 3: Configure</span>  Set class name, mode (polling/subscription)
<span class="text-blue-400">Step 4: Deploy</span>    Pipeline starts collecting data immediately</code></pre>
              <div class="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-primary/10 to-transparent pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"></div>
            </div>

            <h3 class="text-lg font-bold text-on-surface mb-6">Key Concepts</h3>
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="border-b border-outline-variant/20">
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Concept</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Description</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Row Source</td>
                    <td class="py-4 text-on-surface-variant">A parent device node (e.g., AirConditioner_1) that produces one row per poll cycle</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Columns</td>
                    <td class="py-4 text-on-surface-variant">The child attributes selected as data columns (e.g., Temperature, Humidity)</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">NodePath</td>
                    <td class="py-4 text-on-surface-variant">Auto-generated column identifying which device produced each row</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Polling</td>
                    <td class="py-4 text-on-surface-variant">Reads all nodes at a fixed interval (e.g., every 5 seconds)</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Subscription</td>
                    <td class="py-4 text-on-surface-variant">Event-driven: server pushes updates when values change</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Managing Pipelines -->
          <section class="mb-16" id="managing-pipelines">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 4</span>
              <h2 class="text-2xl font-bold text-on-surface">Managing Pipelines</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              The Pipelines dashboard shows all deployed pipelines with their status, row counts, and data flow visualization.
            </p>

            <h3 class="text-lg font-bold text-on-surface mb-6">Pipeline Actions</h3>
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="border-b border-outline-variant/20">
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Action</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Icon</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Description</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Start / Stop</td>
                    <td class="py-4"><span class="material-symbols-outlined text-tertiary text-base">play_circle</span> / <span class="material-symbols-outlined text-error text-base">stop_circle</span></td>
                    <td class="py-4 text-on-surface-variant">Toggle the pipeline on or off without deleting it</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Edit</td>
                    <td class="py-4"><span class="material-symbols-outlined text-primary text-base">edit_square</span></td>
                    <td class="py-4 text-on-surface-variant">Add or remove nodes and row sources from an existing pipeline</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Delete</td>
                    <td class="py-4"><span class="material-symbols-outlined text-error text-base">delete</span></td>
                    <td class="py-4 text-on-surface-variant">Remove the pipeline and its DataSource class (only when stopped)</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Feedback Section -->
          <section class="mt-24 pt-12 border-t border-outline-variant/20 flex flex-col items-center">
            <p class="text-sm font-semibold text-on-surface-variant mb-4">Was this documentation helpful?</p>
            <div class="flex space-x-4">
              <button class="flex items-center space-x-2 px-6 py-2 bg-surface-container-lowest border border-outline-variant/20 rounded-full hover:bg-primary/5 hover:border-primary transition-all group">
                <span class="material-symbols-outlined text-lg group-hover:scale-110 transition-transform">thumb_up</span>
                <span class="text-xs font-bold uppercase tracking-widest">Yes</span>
              </button>
              <button class="flex items-center space-x-2 px-6 py-2 bg-surface-container-lowest border border-outline-variant/20 rounded-full hover:bg-error/5 hover:border-error transition-all group">
                <span class="material-symbols-outlined text-lg group-hover:scale-110 transition-transform">thumb_down</span>
                <span class="text-xs font-bold uppercase tracking-widest">No</span>
              </button>
            </div>
          </section>
        </article>

        <!-- Table of Contents Column -->
        <aside class="hidden lg:block w-64 shrink-0">
          <div class="sticky top-32 space-y-8">
            <div>
              <h4 class="text-[10px] font-bold uppercase tracking-[0.2em] text-on-surface-variant mb-4">On This Page</h4>
              <nav class="space-y-3">
                <a class="block text-xs font-bold border-l-2 pl-4 transition-colors cursor-pointer"
                   [class]="activeSection() === 'getting-started' ? 'text-primary border-primary' : 'text-on-surface-variant border-transparent hover:text-primary'"
                   (click)="scrollTo('getting-started')">Getting Started</a>
                <a class="block text-xs pl-4 transition-colors cursor-pointer"
                   [class]="activeSection() === 'node-explorer' ? 'text-primary font-bold border-l-2 border-primary' : 'text-on-surface-variant hover:text-primary'"
                   (click)="scrollTo('node-explorer')">Node Explorer</a>
                <a class="block text-xs pl-4 transition-colors cursor-pointer"
                   [class]="activeSection() === 'creating-pipelines' ? 'text-primary font-bold border-l-2 border-primary' : 'text-on-surface-variant hover:text-primary'"
                   (click)="scrollTo('creating-pipelines')">Creating Pipelines</a>
                <a class="block text-xs pl-4 transition-colors cursor-pointer"
                   [class]="activeSection() === 'managing-pipelines' ? 'text-primary font-bold border-l-2 border-primary' : 'text-on-surface-variant hover:text-primary'"
                   (click)="scrollTo('managing-pipelines')">Managing Pipelines</a>
              </nav>
            </div>

            <div class="p-6 bg-primary-container/10 rounded-xl">
              <h4 class="text-[10px] font-bold uppercase tracking-[0.2em] text-primary mb-2">Quick Tip</h4>
              <p class="text-xs text-primary leading-relaxed opacity-80">
                Checking a device node (like AirConditioner_1) in the wizard auto-selects all its
                child attributes as columns. You can uncheck any you don't need.
              </p>
            </div>

            <!-- Promo Card -->
            <div class="relative rounded-xl overflow-hidden bg-blue-950 aspect-[4/5] p-6 flex flex-col justify-end group">
              <div class="absolute inset-0 bg-gradient-to-t from-blue-950 via-blue-950/60 to-blue-950/30"></div>
              <div class="absolute inset-0 flex items-center justify-center opacity-20">
                <span class="material-symbols-outlined text-white" style="font-size: 120px">precision_manufacturing</span>
              </div>
              <div class="relative">
                <span class="inline-block px-2 py-1 bg-tertiary-fixed text-on-tertiary-fixed text-[8px] font-black tracking-widest uppercase rounded mb-3">OPC UA</span>
                <h5 class="text-white text-sm font-bold mb-2 leading-snug">Multiple Device Support</h5>
                <p class="text-blue-200 text-[10px] mb-4">Select sibling devices with matching attributes — they merge into one pipeline automatically.</p>
                <a class="text-white text-[10px] font-bold uppercase tracking-widest flex items-center hover:translate-x-1 transition-transform cursor-pointer"
                   (click)="scrollTo('creating-pipelines')">
                  Learn More
                  <span class="material-symbols-outlined text-sm ml-1">arrow_forward</span>
                </a>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </div>
  `,
})
export class DocumentationComponent implements OnInit, OnDestroy {
  activeSection = signal('getting-started');
  private observer: IntersectionObserver | null = null;
  private sectionIds = ['getting-started', 'node-explorer', 'creating-pipelines', 'managing-pipelines'];

  ngOnInit(): void {
    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            this.activeSection.set(entry.target.id);
          }
        }
      },
      { rootMargin: '-20% 0px -60% 0px' }
    );

    // Observe after a tick so the DOM is rendered
    setTimeout(() => {
      for (const id of this.sectionIds) {
        const el = document.getElementById(id);
        if (el) this.observer!.observe(el);
      }
    });
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
  }

  scrollTo(sectionId: string): void {
    this.activeSection.set(sectionId);
    const el = document.getElementById(sectionId);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }
}
