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
          <nav class="flex items-center space-x-2 text-[10px] font-medium uppercase tracking-widest text-on-surface-muted mb-8">
            <a class="hover:text-primary transition-colors cursor-pointer">Home</a>
            <span class="material-symbols-outlined text-[12px]">chevron_right</span>
            <span class="text-on-surface">Documentation</span>
          </nav>

          <h1 class="text-4xl md:text-5xl font-bold tracking-tight text-blue-950 mb-6">OPC UA Console Guide</h1>
          <p class="text-lg text-on-surface-variant leading-relaxed mb-12">
            Learn how to connect to OPC UA servers, browse industrial address spaces, deploy data collection
            business services, and monitor real-time telemetry from your devices.
          </p>

          <!-- Architecture Overview Section -->
          <section class="mb-16 bg-surface-container-low p-8 rounded-xl relative overflow-hidden">
            <div class="relative z-10 grid grid-cols-1 md:grid-cols-2 gap-8 items-center">
              <div>
                <h2 class="text-xl font-semibold mb-4 text-blue-900">How It Works</h2>
                <p class="text-sm text-on-surface-variant leading-relaxed">
                  You describe one device type once — that's a <em>schema</em> — then bind any
                  number of matching devices to it. A business service collects them on a timer
                  or on change, writing one row per device per cycle into a single IRIS table.
                  Nodes are matched by name each time the service connects, so a device is a
                  line of configuration rather than generated code.
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
              Before browsing nodes or creating business services, add at least one OPC UA server.
              You can keep several — each screen that browses lets you pick which one, and the nav
              rail shows a status dot per connection.
            </p>
            <div class="bg-[#1e1e1e] rounded-xl p-6 shadow-2xl relative group overflow-hidden mb-8">
              <div class="flex justify-between items-center mb-4">
                <span class="text-[10px] text-slate-500 font-mono tracking-widest uppercase">Configuration Steps</span>
              </div>
              <pre class="font-mono text-sm leading-6 text-slate-300"><code>1. Click the <span class="text-blue-400">gear</span> in the top right
2. Under <span class="text-blue-400">OPC UA Servers</span>, pick a connection or <span class="text-blue-400">Add Server</span>
3. Give it a display name and a URL
   e.g. <span class="text-green-400">opc.tcp://your-server:4840</span>
4. Choose Security Mode (None or Sign &amp; Encrypt)
   Sign &amp; Encrypt reveals the certificate fields below it
5. Click <span class="text-blue-400">Test Connection</span> to verify
6. Click <span class="text-blue-400">Save Changes</span></code></pre>
              <div class="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-primary/10 to-transparent pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"></div>
            </div>

            <div class="flex items-start gap-3 mb-8 rounded-xl border border-outline-variant/20 bg-surface-container-low px-4 py-3">
              <span class="material-symbols-outlined text-on-surface-variant text-xl shrink-0">info</span>
              <p class="text-sm text-on-surface-variant leading-relaxed">
                Settings are stored in this browser only, including passwords. They don't follow you
                to another machine, and anyone using this browser profile can read them. The
                <strong class="font-semibold">IRIS API Gateway</strong> tab holds the REST endpoint
                this console talks to — separate from the OPC UA servers it collects from.
              </p>
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
                    <td class="py-4 font-mono text-primary font-semibold">Certificates</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">IF SECURE</span></td>
                    <td class="py-4 text-on-surface-variant">
                      Client certificate, private key, trust list, CRL directory and client URI.
                      Shown only for Sign &amp; Encrypt; the URI must match the certificate's
                      subjectAltName or the handshake fails
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Root Node</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">NO</span></td>
                    <td class="py-4 text-on-surface-variant">
                      Where browsing starts. Defaults to node 84 in namespace 0, the standard
                      OPC UA root
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">API Base URL</td>
                    <td class="py-4"><span class="px-2 py-0.5 bg-surface-container rounded text-[10px] font-bold">YES</span></td>
                    <td class="py-4 text-on-surface-variant">
                      On the IRIS API Gateway tab: the REST endpoint of the IRIS backend, with its
                      credentials and the console's auto-refresh interval
                    </td>
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
                    <td class="py-4 text-on-surface-variant">Click any variable node to read its current value, timestamps, data type and status code</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Auto-Refresh</td>
                    <td class="py-4 text-on-surface-variant">
                      Re-reads the open node on a timer. The interval is the console-wide one set
                      on the IRIS API Gateway tab (1&ndash;60 seconds)
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Staleness</td>
                    <td class="py-4 text-on-surface-variant">
                      If a refresh stops succeeding the value is flagged rather than left looking
                      current — the number on screen says when it was last actually read
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Multiple Servers</td>
                    <td class="py-4 text-on-surface-variant">Every configured server appears as its own expandable root, so you can browse them side by side</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Schemas -->
          <section class="mb-16" id="schemas">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 3</span>
              <h2 class="text-2xl font-bold text-on-surface">Schemas</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              A schema is a device <em>type</em>: the columns one device contributes, and the OPC UA
              node names they resolve against. It owns an IRIS table and nothing else — creating one
              starts no collection and stores no device. Schemas are reusable, so several business
              services can share one, and a schema outlives any service built on it.
            </p>
            <div class="bg-[#1e1e1e] rounded-xl p-6 shadow-2xl relative group overflow-hidden mb-8">
              <div class="flex justify-between items-center mb-4">
                <span class="text-[10px] text-slate-500 font-mono tracking-widest uppercase">Building One</span>
              </div>
              <pre class="font-mono text-sm leading-6 text-slate-300"><code><span class="text-blue-400">1. Pick a server</span>    Switching it browses immediately
<span class="text-blue-400">2. Set device</span>       Mark the node that represents <span class="text-amber-400">one</span> device
<span class="text-blue-400">3. Tick nodes</span>       Each becomes a column, named relative to that device
<span class="text-blue-400">4. Save Schema</span>      Names the class and creates the table</code></pre>
              <div class="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-primary/10 to-transparent pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"></div>
            </div>
            <p class="text-on-surface-variant mb-8 leading-relaxed">
              The device you browse is only a <strong class="font-semibold">template</strong>. Its node
              IDs are never stored — they exist to tell the console what this type of device looks
              like. Column types are inferred by reading each node once, and ticking nodes inside a
              sub-folder produces nested <code class="font-mono text-primary text-sm">Parent_Child</code>
              columns in SQL.
            </p>
            <p class="text-on-surface-variant mb-8 leading-relaxed">
              Columns cannot be changed afterwards. Adding one means creating a new schema, because
              the alternative is rewriting a table that already holds rows. Deleting a schema
              <strong class="font-semibold">drops its table and every row in it</strong>, and is
              refused outright while any business service still references it.
            </p>

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
                    <td class="py-4 font-mono text-primary font-semibold">Schema</td>
                    <td class="py-4 text-on-surface-variant">A device type and its table. Reusable, and independent of any business service</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Template Device</td>
                    <td class="py-4 text-on-surface-variant">
                      The node you measure columns against while building. Its own name never becomes
                      part of a column, and its node IDs are not saved
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Columns</td>
                    <td class="py-4 text-on-surface-variant">The child nodes selected as data columns (e.g., Temperature, Humidity). Matched by <em>name</em> on every device</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">NodePath</td>
                    <td class="py-4 text-on-surface-variant">A column added for you, recording which device produced each row</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Table</td>
                    <td class="py-4 text-on-surface-variant">
                      The SQL name to query, e.g. <span class="font-mono">OPCUA_DS.AirCon</span>. The
                      package's dots become an underscore, since a SQL name holds only one
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Creating Business Services -->
          <section class="mb-16" id="creating-pipelines">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 4</span>
              <h2 class="text-2xl font-bold text-on-surface">Creating Business Services</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              A business service is a schema bound to a list of devices. It is one InterSystems
              interoperability config item — the same thing the Management Portal calls a business
              service — and it produces one row per device per cycle in the schema's table.
            </p>
            <div class="bg-[#1e1e1e] rounded-xl p-6 shadow-2xl relative group overflow-hidden mb-8">
              <div class="flex justify-between items-center mb-4">
                <span class="text-[10px] text-slate-500 font-mono tracking-widest uppercase">Steps</span>
              </div>
              <pre class="font-mono text-sm leading-6 text-slate-300"><code><span class="text-blue-400">1. New Business Service</span>  From the dashboard, then choose a schema
<span class="text-blue-400">2. Bind devices</span>         Click them in the tree, or paste a list as text
<span class="text-blue-400">3. Check the coverage</span>   Each device reports how many columns it has
<span class="text-blue-400">4. Create</span>               Created <span class="text-amber-400">stopped</span> — nothing is polled yet
<span class="text-blue-400">5. Press play</span>           Start it from Business Services when ready</code></pre>
              <div class="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-primary/10 to-transparent pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"></div>
            </div>
            <p class="text-on-surface-variant mb-8 leading-relaxed">
              Devices are checked against the schema as you add them, before anything is deployed —
              a device reporting <span class="font-mono">3/4</span> columns will store NULL for the
              one it lacks, and a device resolving nothing at all cannot be bound. Because nodes are
              matched by name on every connect, a device that is offline when the service starts
              begins reporting on its own once it is reachable.
            </p>

            <h3 class="text-lg font-bold text-on-surface mb-6">Settings</h3>
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="border-b border-outline-variant/20">
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Setting</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Description</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Service name</td>
                    <td class="py-4 text-on-surface-variant">
                      The interop identity — what appears in the event log and the Management Portal.
                      <strong class="font-semibold">Permanent once created</strong>; to change it,
                      delete the service and bind the schema again
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Display label</td>
                    <td class="py-4 text-on-surface-variant">Optional friendlier name for this console and the Portal's Comment column. Editable later, and never replaces the name</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Categories</td>
                    <td class="py-4 text-on-surface-variant">
                      How the service is grouped in the Management Portal. Prefilled with
                      <span class="font-mono">OPCUA</span> and the schema name; change or remove
                      either. Organisational only
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Polling</td>
                    <td class="py-4 text-on-surface-variant">Reads every device on a fixed timer. Predictable load; a row per device per cycle even when nothing changed</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Subscription</td>
                    <td class="py-4 text-on-surface-variant">The server pushes values as they change. Lighter on the PLC for values that rarely move, and rows appear only on change</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Managing Business Services -->
          <section class="mb-16" id="managing-pipelines">
            <div class="flex items-center space-x-3 mb-6">
              <span class="inline-block px-3 py-1 bg-tertiary-container text-on-tertiary-container rounded-full text-[10px] font-bold tracking-tighter uppercase">Step 5</span>
              <h2 class="text-2xl font-bold text-on-surface">Managing Business Services</h2>
            </div>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              The dashboard shows every service with its health, row count and flow diagram, and
              re-fetches on a timer so what's on screen stays true. Expand a card for the diagram,
              or collapse them all once the list is long enough that height is the problem.
            </p>

            <h3 class="text-lg font-bold text-on-surface mb-6">Health</h3>
            <p class="text-on-surface-variant mb-6 leading-relaxed">
              Status is the adapter's own verdict, not merely whether the service is switched on —
              enabled and failing are different things, and a card that looked healthy while its
              table stayed empty was the thing this replaced.
            </p>
            <div class="overflow-x-auto mb-12">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="border-b border-outline-variant/20">
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">State</th>
                    <th class="py-4 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Meaning</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Running</td>
                    <td class="py-4 text-on-surface-variant">Connected and collecting</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Starting</td>
                    <td class="py-4 text-on-surface-variant">Enabled, first cycles not finished yet</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Not collecting</td>
                    <td class="py-4 text-on-surface-variant">Enabled but no data is landing — check the event log for the reason</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Running, no rows yet</td>
                    <td class="py-4 text-on-surface-variant">
                      Cycling without errors and still nothing stored. Usually the bound devices
                      don't expose the schema's columns — Edit shows the coverage
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Stopped</td>
                    <td class="py-4 text-on-surface-variant">Switched off, or the production isn't running</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <h3 class="text-lg font-bold text-on-surface mb-6">Service Actions</h3>
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
                    <td class="py-4 text-on-surface-variant">Begin or halt collection. A newly created service is stopped, so this is what puts it to work</td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Edit</td>
                    <td class="py-4"><span class="material-symbols-outlined text-primary text-base">edit_square</span></td>
                    <td class="py-4 text-on-surface-variant">
                      Change which devices it reads, its display label and its categories. The
                      schema and the transport are fixed, so its columns cannot change here.
                      Takes effect without a recompile
                    </td>
                  </tr>
                  <tr class="border-b border-outline-variant/10">
                    <td class="py-4 font-mono text-primary font-semibold">Delete</td>
                    <td class="py-4"><span class="material-symbols-outlined text-error text-base">delete</span></td>
                    <td class="py-4 text-on-surface-variant">
                      Remove the service, only when stopped. Its schema and every collected row are
                      kept — deleting a service is not how you delete data
                    </td>
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
                   [class]="activeSection() === 'schemas' ? 'text-primary font-bold border-l-2 border-primary' : 'text-on-surface-variant hover:text-primary'"
                   (click)="scrollTo('schemas')">Schemas</a>
                <a class="block text-xs pl-4 transition-colors cursor-pointer"
                   [class]="activeSection() === 'creating-pipelines' ? 'text-primary font-bold border-l-2 border-primary' : 'text-on-surface-variant hover:text-primary'"
                   (click)="scrollTo('creating-pipelines')">Creating Business Services</a>
                <a class="block text-xs pl-4 transition-colors cursor-pointer"
                   [class]="activeSection() === 'managing-pipelines' ? 'text-primary font-bold border-l-2 border-primary' : 'text-on-surface-variant hover:text-primary'"
                   (click)="scrollTo('managing-pipelines')">Managing Business Services</a>
              </nav>
            </div>

            <div class="p-6 bg-primary-container/10 rounded-xl">
              <h4 class="text-[10px] font-bold uppercase tracking-[0.2em] text-primary mb-2">Quick Tip</h4>
              <p class="text-xs text-primary leading-relaxed opacity-80">
                Mark the template device before ticking nodes. Columns are named relative to it, so
                the device's own name never becomes part of a column — which is what lets the same
                schema fit AC1, AC2 and AC3.
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
                <h5 class="text-white text-sm font-bold mb-2 leading-snug">One Schema, Many Devices</h5>
                <p class="text-blue-200 text-[10px] mb-4">
                  Bind as many matching devices as you like to a single schema. They share one table,
                  one row each per cycle — and adding another later is one line of configuration.
                </p>
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
  private sectionIds = [
    'getting-started',
    'node-explorer',
    'schemas',
    'creating-pipelines',
    'managing-pipelines',
  ];

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
