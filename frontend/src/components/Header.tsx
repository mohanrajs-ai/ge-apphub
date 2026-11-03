/**
 * Top navigation header displaying Gemini Enterprise AppHub branding,
 * active user badge, Cloud Identity group summary, role preview switcher,
 * Sign Out action, and Light/Dark theme toggle.
 */

import React from 'react';
import { LogOut, Moon, ShieldCheck, Sun, User } from 'lucide-react';
import { useTheme } from '../context/ThemeContext';
import { UserContext } from '../types/catalog';

export interface HeaderProps {
  user: UserContext | null;
  activeDevRole: string;
  onDevRoleChange: (newRole: string) => void;
  onSignOut?: () => void;
}

const AVAILABLE_DEV_ROLES = [
  { value: 'employee', label: 'Standard Employee (Active User Groups)' },
  {
    value: 'mohanraj@mohanrajs.altostrat.com',
    label: 'User: mohanraj@ (HR & Ops Groups)',
  },
  {
    value: 'admin@mohanrajs.altostrat.com',
    label: 'User: admin@ (6 App Groups)',
  },
  { value: 'engineering', label: 'Engineering' },
  { value: 'data-analyst', label: 'Data & FinOps Analyst' },
  { value: 'security', label: 'Security Operations' },
  { value: 'admin', label: 'Platform Admin (All Apps)' },
];

const TECH_MAHINDRA_LOGO_URL =
  'https://www.mahindra.com/sites/default/files/social-thumbnail/TM_Logo_Color_Pos_RGB.webp';

/**
 * Renders the Tech Mahindra brand logo image.
 */
function TechMahindraLogo(): React.ReactElement {
  return (
    <div className="flex h-11 items-center rounded-xl border border-slate-200/80 bg-white px-2.5 py-1 shadow-sm dark:border-slate-700">
      <img
        src={TECH_MAHINDRA_LOGO_URL}
        alt="Tech Mahindra Logo"
        className="h-8 w-auto object-contain"
      />
    </div>
  );
}

/**
 * Renders the top application bar with identity and theme controls.
 */
export function Header({
  user,
  activeDevRole,
  onDevRoleChange,
  onSignOut,
}: HeaderProps): React.ReactElement {
  const { theme, toggleTheme } = useTheme();
  const groupCount = user?.groups?.length ?? 0;

  return (
    <header className="sticky top-0 z-30 border-b border-slate-200/80 bg-white/90 backdrop-blur-md dark:border-slate-800 dark:bg-slate-900/90">
      <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-4 py-3.5 sm:px-6 lg:px-8">
        <div className="flex items-center gap-3.5">
          <TechMahindraLogo />
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-lg font-semibold tracking-tight text-slate-900 dark:text-white">
                Tech-M Gemini AI Hub
              </h1>
              <span className="rounded-full bg-red-50 px-2.5 py-0.5 text-xs font-medium text-red-700 dark:bg-red-950/70 dark:text-red-300">
                Enterprise Catalog
              </span>
            </div>
            <p className="text-xs text-slate-500 dark:text-slate-400">
              Discover and launch approved Gemini Enterprise applications
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 rounded-lg border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-xs dark:border-slate-800 dark:bg-slate-800/60">
            <ShieldCheck
              className="h-3.5 w-3.5 text-indigo-600 dark:text-indigo-400"
              aria-hidden="true"
            />
            <label
              htmlFor="dev-role-select"
              className="font-medium text-slate-600 dark:text-slate-300"
            >
              Preview Role:
            </label>
            <select
              id="dev-role-select"
              aria-label="Preview Role"
              value={activeDevRole}
              onChange={(e) => onDevRoleChange(e.target.value)}
              className="rounded bg-transparent font-semibold text-slate-900 focus:outline-none dark:text-white"
            >
              {AVAILABLE_DEV_ROLES.map((roleOpt) => (
                <option
                  key={roleOpt.value}
                  value={roleOpt.value}
                  className="bg-white text-slate-900 dark:bg-slate-900 dark:text-white"
                >
                  {roleOpt.label}
                </option>
              ))}
            </select>
          </div>

          {user && (
            <div
              className="hidden items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs text-slate-700 sm:flex dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300"
              title={`Roles: ${user.roles.join(', ')}${
                groupCount ? ` | Groups: ${user.groups?.join(', ')}` : ''
              }`}
            >
              <User
                className="h-3.5 w-3.5 text-slate-400"
                aria-hidden="true"
              />
              <span className="font-medium">{user.email}</span>
              {groupCount > 0 && (
                <span className="rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-semibold text-blue-700 dark:bg-blue-950/70 dark:text-blue-300">
                  {groupCount} {groupCount === 1 ? 'Group' : 'Groups'}
                </span>
              )}
            </div>
          )}

          {onSignOut && (
            <button
              type="button"
              onClick={onSignOut}
              aria-label="Sign Out"
              className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-100 dark:border-slate-800 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
            >
              <LogOut className="h-3.5 w-3.5" aria-hidden="true" />
              <span>Sign Out</span>
            </button>
          )}

          <button
            type="button"
            onClick={toggleTheme}
            aria-label="Toggle color theme"
            className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-700 transition hover:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:border-slate-800 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
          >
            {theme === 'dark' ? (
              <Sun className="h-4 w-4 text-amber-400" aria-hidden="true" />
            ) : (
              <Moon className="h-4 w-4 text-slate-600" aria-hidden="true" />
            )}
          </button>
        </div>
      </div>
    </header>
  );
}
