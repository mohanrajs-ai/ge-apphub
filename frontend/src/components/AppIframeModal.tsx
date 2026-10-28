/**
 * Embedded iframe workspace modal/overlay for running a launched Gemini
 * Enterprise application directly inside AppHub without page redirection.
 */

import React from 'react';
import { ArrowLeft, Globe, Sparkles, X } from 'lucide-react';
import { CatalogApplication } from '../types/catalog';

export interface AppIframeModalProps {
  app: CatalogApplication;
  onClose: () => void;
}

/**
 * Renders a full-viewport embedded iframe workspace for the selected GE app.
 */
export function AppIframeModal({
  app,
  onClose,
}: AppIframeModalProps): React.ReactElement {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`${app.display_name} Workspace`}
      className="fixed inset-0 z-50 flex flex-col bg-slate-900/70 backdrop-blur-sm"
    >
      <div className="flex flex-1 flex-col overflow-hidden bg-white shadow-2xl dark:bg-slate-950">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-white px-4 py-3 sm:px-6 dark:border-slate-800 dark:bg-slate-900">
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={onClose}
              aria-label="Close embedded application"
              className="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-slate-50 px-3 py-1.5 text-xs font-semibold text-slate-700 transition hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
            >
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              <span>Back to Catalog</span>
            </button>

            <div className="flex items-center gap-2.5">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-50 text-blue-600 dark:bg-blue-950 dark:text-blue-400">
                <Sparkles className="h-4 w-4" aria-hidden="true" />
              </div>
              <div>
                <h2 className="text-sm font-semibold text-slate-900 dark:text-white">
                  {app.display_name}
                </h2>
                <div className="flex items-center gap-2 text-[11px] text-slate-500 dark:text-slate-400">
                  <span>{app.category}</span>
                  <span>•</span>
                  <span className="inline-flex items-center gap-1">
                    <Globe className="h-3 w-3" aria-hidden="true" />
                    {app.location}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            aria-label="Dismiss workspace"
            className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white"
          >
            <X className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>

        <div className="relative flex-1 bg-slate-100 dark:bg-slate-950">
          <iframe
            src={app.launch_url}
            title={app.display_name}
            className="h-full w-full border-0"
            allow="clipboard-read; clipboard-write; microphone"
          />
        </div>
      </div>
    </div>
  );
}
