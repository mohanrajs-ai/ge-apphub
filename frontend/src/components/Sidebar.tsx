/**
 * Left navigation sidebar for switching between Apps, Skills, and Agents.
 */

import React from 'react';
import { Bot, Clock, LayoutGrid, ShieldCheck, Sparkles } from 'lucide-react';
import { PortalSection } from '../types/catalog';

export interface SidebarProps {
  activeSection: PortalSection;
  onSelectSection: (section: PortalSection) => void;
  appsCount: number;
  skillsCount: number;
  pendingSkillsCount: number;
  approvedSkillsCount?: number;
  isAdmin?: boolean;
}

/**
 * Renders the primary sidebar navigation with Apps, Skills, Agents, and RBAC Admin Governance.
 */
export function Sidebar({
  activeSection,
  onSelectSection,
  appsCount,
  skillsCount,
  pendingSkillsCount,
  approvedSkillsCount,
  isAdmin = false,
}: SidebarProps): React.ReactElement {
  const publishedCount = approvedSkillsCount ?? skillsCount;
  const navItems: Array<{
    id: PortalSection;
    label: string;
    description: string;
    icon: React.ReactNode;
    badge?: React.ReactNode;
  }> = [
    {
      id: 'apps',
      label: 'Apps',
      description: 'Enterprise Search & Assistants',
      icon: <LayoutGrid className="h-4 w-4 shrink-0" aria-hidden="true" />,
      badge: (
        <span className="rounded-full bg-slate-200/80 px-2 py-0.5 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-300">
          {appsCount}
        </span>
      ),
    },
    {
      id: 'skills',
      label: 'Skills',
      description: 'Published AI Skill Hub',
      icon: <Sparkles className="h-4 w-4 shrink-0" aria-hidden="true" />,
      badge: (
        <div className="flex items-center gap-1.5">
          {!isAdmin && pendingSkillsCount > 0 && (
            <span
              title={`${pendingSkillsCount} skill(s) pending admin review`}
              className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-800 dark:bg-amber-950/80 dark:text-amber-300"
            >
              <Clock className="h-3 w-3" aria-hidden="true" />
              {pendingSkillsCount}
            </span>
          )}
          <span className="rounded-full bg-slate-200/80 px-2 py-0.5 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-300">
            {publishedCount}
          </span>
        </div>
      ),
    },
    {
      id: 'agents',
      label: 'Agents',
      description: 'ADK & A2A Agent Registry',
      icon: <Bot className="h-4 w-4 shrink-0" aria-hidden="true" />,
      badge: (
        <span className="rounded-full bg-indigo-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-indigo-700 dark:bg-indigo-950/70 dark:text-indigo-300">
          Soon
        </span>
      ),
    },
  ];

  return (
    <aside
      aria-label="Primary Navigation"
      className="w-full shrink-0 lg:w-64"
    >
      <div className="sticky top-24 rounded-2xl border border-slate-200/80 bg-white p-3 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div className="mb-2 px-3 pt-1">
          <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500">
            Workspace Navigation
          </p>
        </div>

        <nav className="space-y-1">
          {navItems.map((item) => {
            const isActive = activeSection === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => onSelectSection(item.id)}
                aria-current={isActive ? 'page' : undefined}
                className={`flex w-full items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-left transition ${
                  isActive
                    ? 'bg-blue-600 text-white shadow-sm dark:bg-blue-600'
                    : 'text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800/70'
                }`}
              >
                <div className="flex min-w-0 items-center gap-3">
                  <div
                    className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
                      isActive
                        ? 'bg-white/20 text-white'
                        : 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300'
                    }`}
                  >
                    {item.icon}
                  </div>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-semibold">
                      {item.label}
                    </p>
                    <p
                      className={`truncate text-[11px] ${
                        isActive
                          ? 'text-blue-100'
                          : 'text-slate-500 dark:text-slate-400'
                      }`}
                    >
                      {item.description}
                    </p>
                  </div>
                </div>
                <div className="shrink-0">{item.badge}</div>
              </button>
            );
          })}
        </nav>

        {isAdmin && (
          <div className="mt-4 border-t border-slate-200/80 pt-3 dark:border-slate-800">
            <div className="mb-2 px-3">
              <p className="text-[11px] font-semibold uppercase tracking-wider text-indigo-600 dark:text-indigo-400">
                Admin & InfoSec RBAC
              </p>
            </div>
            <button
              type="button"
              onClick={() => onSelectSection('skill-governance')}
              aria-current={
                activeSection === 'skill-governance' ? 'page' : undefined
              }
              className={`flex w-full items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-left transition ${
                activeSection === 'skill-governance'
                  ? 'bg-indigo-600 text-white shadow-sm dark:bg-indigo-600'
                  : 'text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800/70'
              }`}
            >
              <div className="flex min-w-0 items-center gap-3">
                <div
                  className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
                    activeSection === 'skill-governance'
                      ? 'bg-white/20 text-white'
                      : 'bg-indigo-50 text-indigo-600 dark:bg-indigo-950/60 dark:text-indigo-300'
                  }`}
                >
                  <ShieldCheck className="h-4 w-4 shrink-0" aria-hidden="true" />
                </div>
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold">
                    Skill Governance
                  </p>
                  <p
                    className={`truncate text-[11px] ${
                      activeSection === 'skill-governance'
                        ? 'text-indigo-100'
                        : 'text-slate-500 dark:text-slate-400'
                    }`}
                  >
                    Multi-App Eval & InfoSec
                  </p>
                </div>
              </div>
              <div className="flex shrink-0 items-center gap-1">
                {pendingSkillsCount > 0 && (
                  <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-bold text-amber-800 dark:bg-amber-950 dark:text-amber-300">
                    <Clock className="h-3 w-3" aria-hidden="true" />
                    {pendingSkillsCount}
                  </span>
                )}
                <span className="rounded-full bg-slate-200/80 px-2 py-0.5 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-300">
                  {skillsCount}
                </span>
              </div>
            </button>
          </div>
        )}

        {pendingSkillsCount > 0 && (
          <div className="mt-4 rounded-xl border border-amber-200/80 bg-amber-50/80 p-3 text-xs text-amber-900 dark:border-amber-900/50 dark:bg-amber-950/40 dark:text-amber-200">
            <div className="flex items-center gap-1.5 font-semibold">
              <Clock className="h-3.5 w-3.5 shrink-0 text-amber-600 dark:text-amber-400" />
              <span>Pending Skill Share Requests</span>
            </div>
            <p className="mt-1 text-[11px] leading-relaxed text-amber-800/90 dark:text-amber-300/90">
              {pendingSkillsCount} user-created skill
              {pendingSkillsCount === 1 ? ' is' : 's are'} awaiting Gemini
              Enterprise Admin Approval.
            </p>
          </div>
        )}
      </div>
    </aside>
  );
}
