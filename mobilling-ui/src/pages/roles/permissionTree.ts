import type { GroupedPermissions, Permission } from '../../api/roles';

/**
 * Turns the flat permission list into the order a person thinks in:
 *
 *   Section (sidebar group, or Dashboard / Reports / Settings)
 *     └ Module (sub menu, e.g. Expenses)
 *         ├ Menu access   — the menu.* switch that shows the module in the sidebar
 *         ├ Tabs          — the views and features inside the module
 *         └ Actions       — the create / read / update / delete style operations
 *
 * Classification is by name, because that is how permissions are already
 * written: `<module>.<action>` for operations, `<module>.<tab>` for views.
 */

export type PermModule = {
  key: string;
  label: string;
  menu?: Permission;
  tabs: Permission[];
  actions: Permission[];
};

export type PermSection = {
  key: string;
  label: string;
  kind: 'menu' | 'dashboard' | 'reports' | 'settings';
  modules: PermModule[];
};

/** Last-segment tokens that mean "an operation on data" rather than "a view". */
const ACTION_TOKENS = new Set([
  'create', 'read', 'update', 'delete', 'manage', 'view_all', 'submit', 'review', 'approve',
  'approve_collection', 'reject', 'unapprove', 'convert', 'send', 'download', 'date_range',
  'reconcile', 'topup', 'reassign', 'renew', 'transfer', 'manage_dns', 'sso', 'suspend',
  'terminate', 'change_package', 'portal_login', 'portal_password', 'assign', 'cancel',
  'reschedule', 'log', 'verify', 'reply', 'close', 'power', 'resend_receipt', 'extend_due_date',
  'change_date', 'checkin', 'request', 'waive',
]);

/** Sidebar sections in the order the sidebar shows them. */
const SECTION_ORDER = ['Navigation', 'Billing', 'Domains', 'Hosting', 'Linode', 'Support', 'WhatsApp', 'Field Marketing', 'Statutory', 'Expenses', 'Other'];

/**
 * Permission prefixes that belong to a sidebar menu under a different name, so
 * `bills.*` shows inside the Statutory "Bills" menu, not in a separate module.
 */
const MODULE_ALIAS: Record<string, string> = {
  bills: 'statutory_bills',
  client_profile: 'clients',
  credit: 'clients',
  documents: 'invoices',
  field_sessions: 'field_marketing',
  field_targets: 'field_marketing',
  field_visits: 'field_marketing',
  marketing_services: 'field_marketing',
  orders: 'client_subscriptions',
  served: 'served_customers',
  social: 'social_media',
  system_verification_reports: 'system_verifications',
  whatsapp_campaigns: 'whatsapp',
  whatsapp_contacts: 'whatsapp',
  wifi_plans: 'wifi_hotspot',
  wifi_purchases: 'wifi_hotspot',
  wifi_routers: 'wifi_hotspot',
};

/** Modules that have no menu.* permission of their own, placed under the sidebar section they live in. */
const MODULE_SECTION_OVERRIDE: Record<string, string> = {
  attendance: 'Navigation',
};

const OTHER_MODULES = 'Other modules';

function isAction(name: string): boolean {
  return ACTION_TOKENS.has(name.slice(name.indexOf('.') + 1));
}

/** "Staff Reports menu" → "Staff Reports" */
function menuLabel(label: string): string {
  return label.replace(/\s+menu$/i, '').replace(/\s+menu\s+\(.*\)$/i, '');
}

function moduleKeyOf(name: string): string {
  return name.split('.')[0];
}

function sectionRank(label: string): number {
  const i = SECTION_ORDER.indexOf(label);
  return i === -1 ? 999 : i;
}

export function buildPermissionTree(grouped: GroupedPermissions): PermSection[] {
  const sections = new Map<string, PermSection>();
  const modules = new Map<string, PermModule>(); // keyed by module key, one home per module

  const sectionFor = (label: string, kind: PermSection['kind']): PermSection => {
    let s = sections.get(label);
    if (!s) {
      s = { key: label, label, kind, modules: [] };
      sections.set(label, s);
    }
    return s;
  };

  const moduleFor = (key: string, label: string, sectionLabel: string): PermModule => {
    let m = modules.get(key);
    if (!m) {
      m = { key, label, tabs: [], actions: [] };
      modules.set(key, m);
      sectionFor(sectionLabel, 'menu').modules.push(m);
    }
    return m;
  };

  // 1. Sidebar menu items define the sections and the sub menus.
  for (const [group, perms] of Object.entries(grouped.menu ?? {})) {
    for (const p of perms) {
      const key = p.name.replace(/^menu\./, '');
      const m = moduleFor(key, menuLabel(p.label), group);
      m.menu = p;
      m.label = menuLabel(p.label);
    }
  }

  // 2. Operations and views. A module with a menu item reuses it; otherwise it
  //    gets a home under its override section, or "Other modules".
  const homeFor = (name: string, group: string): PermModule => {
    const prefix = moduleKeyOf(name);
    const key = MODULE_ALIAS[prefix] ?? prefix;
    const existing = modules.get(key);
    if (existing) return existing;
    return moduleFor(key, group, MODULE_SECTION_OVERRIDE[key] ?? MODULE_SECTION_OVERRIDE[prefix] ?? OTHER_MODULES);
  };

  for (const [group, perms] of Object.entries(grouped.crud ?? {})) {
    for (const p of perms) {
      const m = homeFor(p.name, group);
      (isAction(p.name) ? m.actions : m.tabs).push(p);
    }
  }

  // 3. Dashboard, Reports and Settings are flat lists: each group is one module of views.
  const flat: [keyof GroupedPermissions, PermSection['kind'], string][] = [
    ['dashboard', 'dashboard', 'Dashboard'],
    ['reports', 'reports', 'Reports'],
    ['settings', 'settings', 'Settings'],
  ];
  for (const [category, kind, label] of flat) {
    for (const [group, perms] of Object.entries(grouped[category] ?? {})) {
      const key = `${category}:${group}`;
      const m: PermModule = { key, label: group, tabs: [...perms], actions: [] };
      modules.set(key, m);
      sectionFor(label, kind).modules.push(m);
    }
  }

  // Sort: sections by sidebar order (dashboard/reports/settings last), modules and items by label.
  const kindRank: Record<PermSection['kind'], number> = { menu: 0, dashboard: 1, reports: 2, settings: 3 };
  const byLabel = <T extends { label: string }>(a: T, b: T) => a.label.localeCompare(b.label);
  const out = [...sections.values()].sort((a, b) =>
    kindRank[a.kind] - kindRank[b.kind] || sectionRank(a.label) - sectionRank(b.label) || a.label.localeCompare(b.label));
  for (const s of out) {
    s.modules.sort(byLabel);
    for (const m of s.modules) {
      m.tabs.sort((a, b) => a.label.localeCompare(b.label));
      m.actions.sort((a, b) => a.label.localeCompare(b.label));
    }
  }
  return out.filter((s) => s.modules.length > 0);
}

/** Keeps the hierarchy intact. A module whose own name matches keeps everything in it. */
export function filterPermissionTree(tree: PermSection[], query: string): PermSection[] {
  const q = query.trim().toLowerCase();
  if (!q) return tree;
  const hit = (p: Permission) => p.label.toLowerCase().includes(q) || p.name.toLowerCase().includes(q);

  return tree
    .map((s) => ({
      ...s,
      modules: s.modules
        .map((m) => {
          if (m.label.toLowerCase().includes(q)) return m;
          const menu = m.menu && hit(m.menu) ? m.menu : undefined;
          const tabs = m.tabs.filter(hit);
          const actions = m.actions.filter(hit);
          if (!menu && tabs.length === 0 && actions.length === 0) return null;
          return { ...m, menu, tabs, actions };
        })
        .filter((m): m is PermModule => m !== null),
    }))
    .filter((s) => s.modules.length > 0);
}

/** Every permission under a module, including its menu item. */
export function modulePermissions(m: PermModule): Permission[] {
  return [...(m.menu ? [m.menu] : []), ...m.tabs, ...m.actions];
}
