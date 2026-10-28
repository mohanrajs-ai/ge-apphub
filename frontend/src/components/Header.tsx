/**
 * Top navigation header displaying Gemini Enterprise AppHub branding,
 * active user badge, role preview switcher, and Light/Dark theme toggle.
 */

import React from 'react';
import { Moon, ShieldCheck, Sparkles, Sun, User } from 'lucide-react';
import { useTheme } from '../context/ThemeContext';
import { UserContext } from '../types/catalog';

export interface HeaderProps {
  user: UserContext | null;
  activeDevRole: string;
  onDevRoleChange: (newRole: string) => void;
}

const AVAILABLE_DEV_ROLES = [
  { value: 'employee', label: 'Standard Employee' },
  { value: 'engineering', label: 'Engineering' },
  { value: 'data-analyst', label: 'Data & FinOps Analyst' },
  { value: 'security', label: 'Security Operations' },
  { value: 'admin', label: 'Platform Admin (All Apps)' },
];

/**
 * Renders the top application bar with identity and theme controls.
 */
export function Header({
  user,
  activeDevRole,
  onDevRoleChange,
}: HeaderProps): React.ReactElement {
  const { theme, toggleTheme } = useTheme();

  return (
    <header className="sticky top-0 z-30 border-b border-slate-200/80 bg-white/90 backdrop-blur-md dark:border-slate-800 dark:bg-slate-900/90">
      <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-4 py-3.5 sm:px-6 lg:px-8">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-blue-600 via-indigo-600 to-purple-600 text-white shadow-sm">
            <Sparkles className="h-5 w-5" aria-hidden="true" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-lg font-semibold tracking-tight text-slate-900 dark:text-white">
                Gemini Enterprise AppHub
              </h1>
              <span className="rounded-full bg-blue-50 px-2.5 py-0.5 text-xs font-medium text-blue-700 dark:bg-blue-950/70 dark:text-blue-300">
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
              title={`Roles: ${user.roles.join(', ')}`}
            >
              <User
                className="h-3.5 w-3.5 text-slate-400"
                aria-hidden="true"
              />
              <span className="font-medium">{user.email}</span>
            </div>
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
