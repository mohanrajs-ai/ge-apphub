/**
 * Responsive grid rendering Gemini Enterprise application cards,
 * skeleton placeholders, and actionable empty states.
 */

import React from 'react';
import { FolderSearch, RotateCcw } from 'lucide-react';
import { CatalogApplication } from '../types/catalog';
import { AppCard } from './AppCard';

export interface CatalogGridProps {
  apps: CatalogApplication[];
  loading: boolean;
  onResetFilters: () => void;
  onSelectTag?: (tag: string) => void;
}

/**
 * Renders the application card grid or appropriate loading/empty state.
 */
export function CatalogGrid({
  apps,
  loading,
  onResetFilters,
  onSelectTag,
}: CatalogGridProps): React.ReactElement {
  if (loading) {
    return (
      <div
        aria-label="Loading applications"
        className="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3"
      >
        {[1, 2, 3, 4, 5, 6].map((item) => (
          <div
            key={item}
            className="h-64 animate-pulse rounded-2xl border border-slate-200 bg-white p-5 dark:border-slate-800 dark:bg-slate-900"
          >
            <div className="h-11 w-11 rounded-xl bg-slate-200 dark:bg-slate-800" />
            <div className="mt-4 h-5 w-3/4 rounded bg-slate-200 dark:bg-slate-800" />
            <div className="mt-3 h-3 w-full rounded bg-slate-100 dark:bg-slate-800/70" />
            <div className="mt-2 h-3 w-5/6 rounded bg-slate-100 dark:bg-slate-800/70" />
          </div>
        ))}
      </div>
    );
  }

  if (apps.length === 0) {
    return (
      <div className="mt-8 flex flex-col items-center justify-center rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-14 text-center dark:border-slate-800 dark:bg-slate-900">
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400">
          <FolderSearch className="h-6 w-6" aria-hidden="true" />
        </div>
        <h3 className="mt-4 text-base font-semibold text-slate-900 dark:text-white">
          No matching applications found
        </h3>
        <p className="mt-1 max-w-md text-sm text-slate-500 dark:text-slate-400">
          No Gemini Enterprise applications matched your current search or
          category filters. Try broadening your query or resetting filters.
        </p>
        <button
          type="button"
          onClick={onResetFilters}
          className="mt-5 inline-flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-blue-700"
        >
          <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
          Reset all filters
        </button>
      </div>
    );
  }

  return (
    <div className="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      {apps.map((app) => (
        <AppCard key={app.engine_id} app={app} onSelectTag={onSelectTag} />
      ))}
    </div>
  );
}
