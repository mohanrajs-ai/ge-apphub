/**
 * Sign-In gate component for authenticating with Google Workspace identity
 * and resolving Cloud Identity group memberships.
 */

import React, { useState } from 'react';
import { ArrowRight, KeyRound, ShieldCheck, Users } from 'lucide-react';
import { SuggestedUser } from '../types/catalog';

const TECH_MAHINDRA_LOGO_URL =
  'https://www.mahindra.com/sites/default/files/social-thumbnail/TM_Logo_Color_Pos_RGB.webp';

export interface LoginScreenProps {
  suggestedUsers: SuggestedUser[];
  loading: boolean;
  error: string | null;
  onLoginEmail: (email: string) => void;
}

/**
 * Renders the dedicated Sign-In experience before entering the AppHub portal.
 */
export function LoginScreen({
  suggestedUsers,
  loading,
  error,
  onLoginEmail,
}: LoginScreenProps): React.ReactElement {
  const [emailInput, setEmailInput] = useState<string>('');

  function handleSubmit(e: React.FormEvent): void {
    e.preventDefault();
    const trimmed = emailInput.trim().toLowerCase();
    if (trimmed) {
      onLoginEmail(trimmed);
    }
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-slate-50 px-4 py-12 dark:bg-slate-950">
      <div className="w-full max-w-md rounded-2xl border border-slate-200/90 bg-white p-8 shadow-lg dark:border-slate-800 dark:bg-slate-900">
        <div className="flex flex-col items-center text-center">
          <div className="flex h-12 items-center rounded-xl border border-slate-200/80 bg-white px-3 py-1.5 shadow-sm dark:border-slate-700">
            <img
              src={TECH_MAHINDRA_LOGO_URL}
              alt="Tech Mahindra Logo"
              className="h-8 w-auto object-contain"
            />
          </div>
          <h1 className="mt-4 text-xl font-bold tracking-tight text-slate-900 dark:text-white">
            Sign in to Tech-M Gemini AI Hub
          </h1>
          <p className="mt-1.5 text-xs leading-relaxed text-slate-500 dark:text-slate-400">
            Sign in with your Google Identity account to view and launch the
            Gemini Enterprise applications authorized for your Cloud Identity
            groups.
          </p>
        </div>

        {error && (
          <div
            role="alert"
            className="mt-4 rounded-xl border border-red-200 bg-red-50 px-3.5 py-2.5 text-xs font-medium text-red-700 dark:border-red-900/60 dark:bg-red-950/50 dark:text-red-300"
          >
            {error}
          </div>
        )}

        {suggestedUsers.length > 0 && (
          <div className="mt-6">
            <p className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
              <Users className="h-3.5 w-3.5 text-blue-600 dark:text-blue-400" />
              Select Workspace Account
            </p>
            <div className="mt-2.5 space-y-2.5">
              {suggestedUsers.map((account) => (
                <button
                  key={account.email}
                  type="button"
                  disabled={loading}
                  onClick={() => onLoginEmail(account.email)}
                  className="group flex w-full items-center justify-between rounded-xl border border-slate-200 bg-slate-50/70 px-4 py-3 text-left transition hover:border-blue-500 hover:bg-blue-50/50 disabled:opacity-50 dark:border-slate-800 dark:bg-slate-800/50 dark:hover:border-blue-400 dark:hover:bg-blue-950/40"
                >
                  <div>
                    <p className="text-sm font-semibold text-slate-900 group-hover:text-blue-600 dark:text-white dark:group-hover:text-blue-400">
                      {account.label}
                    </p>
                    <p className="text-xs font-medium text-blue-600 dark:text-blue-400">
                      {account.email}
                    </p>
                    <p className="mt-0.5 text-[11px] text-slate-500 dark:text-slate-400">
                      {account.description}
                    </p>
                  </div>
                  <ArrowRight className="h-4 w-4 shrink-0 text-slate-400 transition group-hover:translate-x-0.5 group-hover:text-blue-600 dark:group-hover:text-blue-400" />
                </button>
              ))}
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-6 border-t border-slate-100 pt-5 dark:border-slate-800">
          <label
            htmlFor="workspace-email-input"
            className="block text-xs font-semibold text-slate-700 dark:text-slate-300"
          >
            Or sign in with Google Workspace email
          </label>
          <div className="mt-2 flex gap-2">
            <input
              id="workspace-email-input"
              type="email"
              value={emailInput}
              onChange={(e) => setEmailInput(e.target.value)}
              placeholder="user@mohanrajs.altostrat.com"
              className="flex-1 rounded-xl border border-slate-200 bg-slate-50 px-3.5 py-2 text-sm text-slate-900 placeholder-slate-400 focus:border-blue-600 focus:bg-white focus:outline-none dark:border-slate-700 dark:bg-slate-800 dark:text-white"
            />
            <button
              type="submit"
              disabled={loading || !emailInput.trim()}
              className="inline-flex items-center gap-1.5 rounded-xl bg-blue-600 px-4 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-blue-700 disabled:opacity-50"
            >
              <KeyRound className="h-3.5 w-3.5" aria-hidden="true" />
              <span>Sign In</span>
            </button>
          </div>
        </form>

        <div className="mt-5 flex items-center justify-center gap-1.5 text-[11px] text-slate-400">
          <ShieldCheck className="h-3.5 w-3.5 text-emerald-500" />
          <span>Protected by Google Cloud Identity & Engine IAM Policies</span>
        </div>
      </div>
    </div>
  );
}
