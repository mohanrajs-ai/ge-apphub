/**
 * Individual Gemini Enterprise Application Card component.
 */

import React from 'react';
import {
  BarChart3,
  Code2,
  Globe,
  Headphones,
  Play,
  Search,
  ShieldAlert,
  Sparkles,
  Users,
} from 'lucide-react';
import { CatalogApplication } from '../types/catalog';

export interface AppCardProps {
  app: CatalogApplication;
  onLaunchApp: (app: CatalogApplication) => void;
  onSelectTag?: (tag: string) => void;
}

function renderAppIcon(iconName: string): React.ReactElement {
  switch (iconName) {
    case 'Search':
      return <Search className="h-5 w-5" aria-hidden="true" />;
    case 'Code2':
      return <Code2 className="h-5 w-5" aria-hidden="true" />;
    case 'BarChart3':
      return <BarChart3 className="h-5 w-5" aria-hidden="true" />;
    case 'Headphones':
      return <Headphones className="h-5 w-5" aria-hidden="true" />;
    case 'Users':
      return <Users className="h-5 w-5" aria-hidden="true" />;
    case 'ShieldAlert':
      return <ShieldAlert className="h-5 w-5" aria-hidden="true" />;
    default:
      return <Sparkles className="h-5 w-5" aria-hidden="true" />;
  }
}

/**
 * Renders a Material 3 / Cloud Console-inspired card for a GE application.
 */
export function AppCard({
  app,
  onLaunchApp,
  onSelectTag,
}: AppCardProps): React.ReactElement {
  return (
    <article className="group flex flex-col justify-between rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-blue-500/60 hover:shadow-md dark:border-slate-800 dark:bg-slate-900 dark:hover:border-blue-400/60">
      <div>
        <div className="flex items-start justify-between gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-blue-600 dark:bg-blue-950/80 dark:text-blue-400">
            {renderAppIcon(app.icon_name)}
          </div>
          <div className="flex flex-wrap items-center justify-end gap-1.5">
            {app.featured && (
              <span className="rounded-full bg-gradient-to-r from-blue-600 to-indigo-600 px-2.5 py-0.5 text-[11px] font-semibold text-white">
                Featured
              </span>
            )}
            <span className="rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-700 dark:bg-slate-800 dark:text-slate-300">
              {app.category}
            </span>
          </div>
        </div>

        <h2 className="mt-4 text-base font-semibold text-slate-900 group-hover:text-blue-600 dark:text-white dark:group-hover:text-blue-400">
          {app.display_name}
        </h2>

        <p className="mt-1 text-xs font-medium text-slate-500 dark:text-slate-400">
          Department: {app.department}
        </p>

        <p className="mt-2.5 line-clamp-3 text-sm leading-relaxed text-slate-600 dark:text-slate-300">
          {app.description}
        </p>

        <div className="mt-4 flex flex-wrap gap-1.5">
          {app.tags.map((tag) => (
            <button
              key={tag}
              type="button"
              onClick={() => onSelectTag?.(tag)}
              className="rounded-md bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-slate-600 transition hover:bg-blue-50 hover:text-blue-700 dark:bg-slate-800 dark:text-slate-400 dark:hover:bg-blue-950/60 dark:hover:text-blue-300"
            >
              #{tag}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-5 flex items-center justify-between border-t border-slate-100 pt-4 dark:border-slate-800">
        <div className="flex items-center gap-1.5 text-xs text-slate-400">
          <Globe className="h-3.5 w-3.5" aria-hidden="true" />
          <span>{app.location}</span>
        </div>

        <button
          type="button"
          onClick={() => onLaunchApp(app)}
          aria-label={`Launch App ${app.display_name}`}
          className="inline-flex items-center gap-1.5 rounded-xl bg-blue-600 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-slate-900"
        >
          <span>Launch App</span>
          <Play className="h-3.5 w-3.5 fill-current" aria-hidden="true" />
        </button>
      </div>
    </article>
  );
}
