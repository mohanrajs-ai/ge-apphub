/**
 * Skills catalog, 5-stage ADK & InfoSec governance workflow, and Skill Registry section.
 */

import React, { useMemo, useState } from 'react';
import {
  BookOpen,
  CheckCircle2,
  Clock,
  FileCode,
  FolderGit2,
  Mail,
  PackageCheck,
  Search,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  UserCheck,
  Users,
  X,
  XCircle,
} from 'lucide-react';
import {
  DiscoveredSkill,
  SkillRegistryItem,
  SkillWorkflowItem,
  WorkflowEmailItem,
} from '../types/catalog';

export interface SkillsSectionProps {
  skills: DiscoveredSkill[];
  registrySkills?: SkillRegistryItem[];
  workflowEmails?: WorkflowEmailItem[];
  pendingReviewCount: number;
  approvedCount: number;
  loading: boolean;
  onApproveSkill?: (skillId: string) => void;
  onRejectSkill?: (skillId: string) => void;
}

type SkillTab = 'PENDING_REVIEW' | 'APPROVED' | 'REGISTRY' | 'EMAILS' | 'ALL';

function formatShortDate(isoString?: string | null): string {
  if (!isoString) {
    return '—';
  }
  const parsed = new Date(isoString);
  if (Number.isNaN(parsed.getTime())) {
    return isoString;
  }
  return parsed.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function cleanPrincipal(raw: string): string {
  return raw.replace(/^(user|group):/i, '');
}

/**
 * Renders the 5-stage visual workflow pipeline stepper for a skill.
 */
function WorkflowStepper({
  workflow,
}: {
  workflow?: SkillWorkflowItem | null;
}): React.ReactElement | null {
  if (!workflow) {
    return null;
  }

  const evalDone = workflow.eval_status === 'PASSED';
  const infosecDone = workflow.infosec_status === 'PASSED';
  const approvedDone = workflow.approval_status === 'APPROVED';
  const rejected = workflow.approval_status === 'REJECTED';
  const registryDone = Boolean(workflow.registry_id);
  const sharedDone = Boolean(workflow.shared_in_ge);

  const stages = [
    {
      label: '1. Skill Eval Agent',
      sub: evalDone ? `Passed (${workflow.eval_score}/100)` : workflow.eval_status,
      state: evalDone ? 'done' : 'failed',
    },
    {
      label: '2. InfoSec Agent',
      sub: infosecDone
        ? `Passed (${workflow.infosec_risk_level} Risk)`
        : workflow.infosec_status,
      state: infosecDone ? 'done' : 'failed',
    },
    {
      label: '3. InfoSec Approval',
      sub: approvedDone
        ? `Approved (${workflow.approved_by || 'InfoSec'})`
        : rejected
          ? 'Rejected'
          : 'Email Sent • Awaiting Review',
      state: approvedDone ? 'done' : rejected ? 'failed' : 'active',
    },
    {
      label: '4. Skill Registry',
      sub: registryDone ? `Published (${workflow.registry_id})` : 'Pending',
      state: registryDone ? 'done' : 'pending',
    },
    {
      label: '5. Share to App',
      sub: sharedDone ? 'Shared in GE App' : 'Pending',
      state: sharedDone ? 'done' : 'pending',
    },
  ];

  return (
    <div className="mt-4 rounded-xl border border-slate-200/90 bg-slate-50/90 p-3.5 dark:border-slate-800 dark:bg-slate-950/70">
      <div className="mb-2.5 flex items-center justify-between">
        <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
          5-Stage Governance Workflow ({workflow.workflow_id})
        </span>
        <span
          className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ${
            workflow.status === 'COMPLETED'
              ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300'
              : workflow.status === 'REJECTED' || workflow.status === 'FAILED'
                ? 'bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-300'
                : 'bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300'
          }`}
        >
          {workflow.current_stage.replace(/_/g, ' ')}
        </span>
      </div>

      <div className="grid gap-2 sm:grid-cols-5">
        {stages.map((st) => (
          <div
            key={st.label}
            className={`rounded-lg border px-2.5 py-2 text-left ${
              st.state === 'done'
                ? 'border-emerald-200 bg-emerald-50/80 text-emerald-950 dark:border-emerald-900/50 dark:bg-emerald-950/30 dark:text-emerald-200'
                : st.state === 'active'
                  ? 'border-amber-300 bg-amber-50 text-amber-950 dark:border-amber-800 dark:bg-amber-950/50 dark:text-amber-200'
                  : st.state === 'failed'
                    ? 'border-red-300 bg-red-50 text-red-950 dark:border-red-900 dark:bg-red-950/40 dark:text-red-200'
                    : 'border-slate-200 bg-white/70 text-slate-400 dark:border-slate-800 dark:bg-slate-900/50 dark:text-slate-500'
            }`}
          >
            <p className="text-[11px] font-bold leading-tight">{st.label}</p>
            <p className="mt-0.5 truncate text-[10px] opacity-90">{st.sub}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * Renders the Gemini Enterprise Skills tab view with 5-stage workflow, Registry, and Email Outbox.
 */
export function SkillsSection({
  skills,
  registrySkills = [],
  workflowEmails = [],
  pendingReviewCount,
  approvedCount,
  loading,
  onApproveSkill,
  onRejectSkill,
}: SkillsSectionProps): React.ReactElement {
  const [activeTab, setActiveTab] = useState<SkillTab>('PENDING_REVIEW');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [selectedEngineId, setSelectedEngineId] = useState<string>('');
  const [selectedSkill, setSelectedSkill] = useState<DiscoveredSkill | null>(
    null,
  );
  const [actionBusyId, setActionBusyId] = useState<string | null>(null);

  const engineOptions = useMemo(() => {
    const unique = new Set<string>();
    skills.forEach((s) => {
      if (s.engine_id) {
        unique.add(s.engine_id);
      }
    });
    return Array.from(unique).sort();
  }, [skills]);

  const filteredSkills = useMemo(() => {
    const needle = searchQuery.trim().toLowerCase();
    return skills.filter((skill) => {
      if (
        activeTab === 'PENDING_REVIEW' &&
        skill.review_status !== 'PENDING_REVIEW'
      ) {
        return false;
      }
      if (activeTab === 'APPROVED' && skill.review_status !== 'APPROVED') {
        return false;
      }
      if (selectedEngineId && skill.engine_id !== selectedEngineId) {
        return false;
      }
      if (!needle) {
        return true;
      }
      const proposalPrincipals = skill.iam_proposals
        .map((p) => p.principal)
        .join(' ');
      const searchable = [
        skill.display_name,
        skill.description,
        skill.engine_id,
        skill.app_display_name,
        skill.owner_email,
        proposalPrincipals,
      ]
        .join(' ')
        .toLowerCase();
      return searchable.includes(needle);
    });
  }, [skills, activeTab, selectedEngineId, searchQuery]);

  async function handleApproveClick(skillId: string): Promise<void> {
    if (!onApproveSkill) {
      return;
    }
    setActionBusyId(skillId);
    try {
      await Promise.resolve(onApproveSkill(skillId));
    } finally {
      setActionBusyId(null);
    }
  }

  async function handleRejectClick(skillId: string): Promise<void> {
    if (!onRejectSkill) {
      return;
    }
    setActionBusyId(skillId);
    try {
      await Promise.resolve(onRejectSkill(skillId));
    } finally {
      setActionBusyId(null);
    }
  }

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-white">
            Gemini Enterprise Skills & Governance Workflow
          </h2>
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
            Automated 5-stage pipeline: 1. Skill Evaluation ADK Agent → 2.
            InfoSec ADK Agent → 3. InfoSec Approval → 4. Skill Registry → 5.
            Share to GE App.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <div className="rounded-xl border border-amber-200 bg-amber-50/80 px-3.5 py-2 text-xs dark:border-amber-900/60 dark:bg-amber-950/40">
            <span className="font-semibold text-amber-900 dark:text-amber-200">
              Pending Review:{' '}
            </span>
            <span className="font-bold text-amber-700 dark:text-amber-300">
              {pendingReviewCount}
            </span>
          </div>
          <div className="rounded-xl border border-emerald-200 bg-emerald-50/80 px-3.5 py-2 text-xs dark:border-emerald-900/60 dark:bg-emerald-950/40">
            <span className="font-semibold text-emerald-900 dark:text-emerald-200">
              Approved:{' '}
            </span>
            <span className="font-bold text-emerald-700 dark:text-emerald-300">
              {approvedCount}
            </span>
          </div>
        </div>
      </div>

      {/* Tabs: Pending Review | Approved & Shared | Skill Registry | InfoSec Emails | All Skills */}
      <div
        role="tablist"
        aria-label="Skill Review Status Tabs"
        className="mb-6 flex flex-wrap items-center gap-2 border-b border-slate-200 pb-3 dark:border-slate-800"
      >
        <button
          type="button"
          role="tab"
          aria-selected={activeTab === 'PENDING_REVIEW'}
          onClick={() => setActiveTab('PENDING_REVIEW')}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition ${
            activeTab === 'PENDING_REVIEW'
              ? 'bg-amber-500 text-white shadow-sm'
              : 'bg-white text-slate-700 hover:bg-slate-100 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800'
          }`}
        >
          <Clock className="h-4 w-4" aria-hidden="true" />
          <span>Pending Review</span>
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
              activeTab === 'PENDING_REVIEW'
                ? 'bg-white/25 text-white'
                : 'bg-amber-100 text-amber-800 dark:bg-amber-950/80 dark:text-amber-300'
            }`}
          >
            {pendingReviewCount}
          </span>
        </button>

        <button
          type="button"
          role="tab"
          aria-selected={activeTab === 'APPROVED'}
          onClick={() => setActiveTab('APPROVED')}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition ${
            activeTab === 'APPROVED'
              ? 'bg-emerald-600 text-white shadow-sm'
              : 'bg-white text-slate-700 hover:bg-slate-100 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800'
          }`}
        >
          <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
          <span>Approved & Shared</span>
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
              activeTab === 'APPROVED'
                ? 'bg-white/25 text-white'
                : 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950/80 dark:text-emerald-300'
            }`}
          >
            {approvedCount}
          </span>
        </button>

        <button
          type="button"
          role="tab"
          aria-selected={activeTab === 'REGISTRY'}
          onClick={() => setActiveTab('REGISTRY')}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition ${
            activeTab === 'REGISTRY'
              ? 'bg-indigo-600 text-white shadow-sm'
              : 'bg-white text-slate-700 hover:bg-slate-100 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800'
          }`}
        >
          <PackageCheck className="h-4 w-4" aria-hidden="true" />
          <span>Skill Registry</span>
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
              activeTab === 'REGISTRY'
                ? 'bg-white/25 text-white'
                : 'bg-indigo-100 text-indigo-800 dark:bg-indigo-950/80 dark:text-indigo-300'
            }`}
          >
            {registrySkills.length}
          </span>
        </button>

        <button
          type="button"
          role="tab"
          aria-selected={activeTab === 'EMAILS'}
          onClick={() => setActiveTab('EMAILS')}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition ${
            activeTab === 'EMAILS'
              ? 'bg-purple-600 text-white shadow-sm'
              : 'bg-white text-slate-700 hover:bg-slate-100 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800'
          }`}
        >
          <Mail className="h-4 w-4" aria-hidden="true" />
          <span>InfoSec Emails</span>
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
              activeTab === 'EMAILS'
                ? 'bg-white/25 text-white'
                : 'bg-purple-100 text-purple-800 dark:bg-purple-950/80 dark:text-purple-300'
            }`}
          >
            {workflowEmails.length}
          </span>
        </button>

        <button
          type="button"
          role="tab"
          aria-selected={activeTab === 'ALL'}
          onClick={() => setActiveTab('ALL')}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition ${
            activeTab === 'ALL'
              ? 'bg-blue-600 text-white shadow-sm'
              : 'bg-white text-slate-700 hover:bg-slate-100 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800'
          }`}
        >
          <Sparkles className="h-4 w-4" aria-hidden="true" />
          <span>All Skills</span>
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
              activeTab === 'ALL'
                ? 'bg-white/25 text-white'
                : 'bg-slate-200 text-slate-700 dark:bg-slate-800 dark:text-slate-300'
            }`}
          >
            {skills.length}
          </span>
        </button>
      </div>

      {/* Tab Content: Skill Registry */}
      {activeTab === 'REGISTRY' ? (
        registrySkills.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-12 text-center dark:border-slate-800 dark:bg-slate-900">
            <PackageCheck className="mx-auto h-10 w-10 text-slate-400" />
            <h3 className="mt-3 text-base font-semibold text-slate-900 dark:text-white">
              No published skills in the Skill Registry yet
            </h3>
            <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
              Approve a pending skill in the Pending Review tab to publish it to
              the Enterprise Skill Registry (Stage 4) and share it to the GE App
              (Stage 5).
            </p>
          </div>
        ) : (
          <div className="grid gap-5 lg:grid-cols-2">
            {registrySkills.map((reg) => (
              <article
                key={reg.registry_id}
                className="rounded-2xl border border-indigo-200/80 bg-white p-6 shadow-sm dark:border-indigo-900/50 dark:bg-slate-900"
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="text-base font-bold text-slate-900 dark:text-white">
                        {reg.display_name}
                      </h3>
                      <span className="rounded-md bg-indigo-100 px-2 py-0.5 font-mono text-xs font-semibold text-indigo-800 dark:bg-indigo-950 dark:text-indigo-300">
                        v{reg.version}
                      </span>
                    </div>
                    <p className="mt-0.5 font-mono text-xs text-slate-500">
                      Registry ID: {reg.registry_id} • App:{' '}
                      {reg.app_display_name}
                    </p>
                  </div>
                  <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-900 dark:bg-emerald-950 dark:text-emerald-200">
                    <ShieldCheck className="h-3.5 w-3.5" />
                    Published & Shared
                  </span>
                </div>
                <p className="mt-3 text-sm text-slate-600 dark:text-slate-300">
                  {reg.description}
                </p>
                <div className="mt-4 grid gap-2 rounded-xl bg-slate-50 p-3 text-xs sm:grid-cols-3 dark:bg-slate-950">
                  <div>
                    <span className="text-slate-400">Eval Score:</span>{' '}
                    <span className="font-bold text-emerald-600">
                      {reg.eval_score}/100
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-400">InfoSec Risk:</span>{' '}
                    <span className="font-bold text-emerald-600">
                      {reg.infosec_risk_level}
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-400">Approved By:</span>{' '}
                    <span className="font-mono font-semibold">
                      {reg.approved_by}
                    </span>
                  </div>
                </div>
              </article>
            ))}
          </div>
        )
      ) : activeTab === 'EMAILS' ? (
        /* Tab Content: InfoSec Approval Emails */
        workflowEmails.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-12 text-center dark:border-slate-800 dark:bg-slate-900">
            <Mail className="mx-auto h-10 w-10 text-slate-400" />
            <h3 className="mt-3 text-base font-semibold text-slate-900 dark:text-white">
              No InfoSec notification emails recorded yet
            </h3>
          </div>
        ) : (
          <div className="space-y-4">
            {workflowEmails.map((em) => (
              <div
                key={em.id}
                className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900"
              >
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 pb-3 dark:border-slate-800">
                  <div>
                    <p className="text-sm font-bold text-slate-900 dark:text-white">
                      {em.subject}
                    </p>
                    <p className="text-xs text-slate-500">
                      To: <span className="font-mono">{em.recipient_email}</span>{' '}
                      • Sent: {formatShortDate(em.created_at)}
                    </p>
                  </div>
                  <span className="rounded-full bg-purple-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-purple-800 dark:bg-purple-950 dark:text-purple-300">
                    {em.delivery_status}
                  </span>
                </div>
                <pre className="mt-3 whitespace-pre-wrap rounded-xl bg-slate-50 p-3.5 font-mono text-xs text-slate-700 dark:bg-slate-950 dark:text-slate-300">
                  {em.body_text}
                </pre>
              </div>
            ))}
          </div>
        )
      ) : (
        /* Tab Content: Pending Review / Approved / All Skills */
        <>
          <div className="mb-6 flex flex-wrap items-center gap-3 rounded-2xl border border-slate-200/80 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div className="relative min-w-[240px] flex-1">
              <Search
                className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400"
                aria-hidden="true"
              />
              <input
                type="search"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search skills by name, description, owner, or requested recipient..."
                aria-label="Search skills"
                className="w-full rounded-xl border border-slate-200 bg-slate-50 py-2 pl-10 pr-4 text-sm text-slate-900 placeholder:text-slate-400 focus:border-blue-500 focus:bg-white focus:outline-none dark:border-slate-700 dark:bg-slate-800/80 dark:text-slate-100"
              />
            </div>

            <select
              aria-label="Filter by GE Application"
              value={selectedEngineId}
              onChange={(e) => setSelectedEngineId(e.target.value)}
              className="rounded-xl border border-slate-200 bg-slate-50 px-3.5 py-2 text-sm text-slate-700 focus:border-blue-500 focus:outline-none dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200"
            >
              <option value="">All GE Applications</option>
              {engineOptions.map((eng) => (
                <option key={eng} value={eng}>
                  {eng}
                </option>
              ))}
            </select>
          </div>

          {loading ? (
            <div className="grid gap-5 md:grid-cols-2">
              {[1, 2].map((n) => (
                <div
                  key={n}
                  className="h-64 animate-pulse rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900"
                />
              ))}
            </div>
          ) : filteredSkills.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-12 text-center dark:border-slate-800 dark:bg-slate-900">
              <Sparkles className="mx-auto h-10 w-10 text-slate-400" />
              <h3 className="mt-3 text-base font-semibold text-slate-900 dark:text-white">
                No skills found in this view
              </h3>
              <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                {activeTab === 'PENDING_REVIEW'
                  ? 'No skills currently have pending share requests awaiting Admin Approval.'
                  : 'Try switching tabs or clearing your search filters.'}
              </p>
            </div>
          ) : (
            <div className="grid gap-5 lg:grid-cols-1">
              {filteredSkills.map((skill) => {
                const isPending = skill.review_status === 'PENDING_REVIEW';
                const isApproved = skill.review_status === 'APPROVED';

                return (
                  <article
                    key={skill.skill_id}
                    className="flex flex-col justify-between rounded-2xl border border-slate-200/90 bg-white p-6 shadow-sm transition hover:shadow-md dark:border-slate-800 dark:bg-slate-900"
                  >
                    <div>
                      {/* Top Row: Icon, Name, and Status Badge */}
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex items-start gap-3">
                          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-amber-500/10 text-amber-600 dark:bg-amber-500/20 dark:text-amber-300">
                            <BookOpen className="h-5 w-5" aria-hidden="true" />
                          </div>
                          <div>
                            <div className="flex flex-wrap items-center gap-2">
                              <h3 className="text-base font-bold text-slate-900 dark:text-white">
                                {skill.display_name}
                              </h3>
                              {skill.subfiles.map((sf) => (
                                <span
                                  key={sf.file_name}
                                  className="inline-flex items-center gap-1 rounded-md bg-slate-100 px-2 py-0.5 font-mono text-[11px] font-medium text-slate-600 dark:bg-slate-800 dark:text-slate-300"
                                >
                                  <FileCode className="h-3 w-3" />
                                  {sf.file_name}
                                </span>
                              ))}
                            </div>
                            <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                              GE Application:{' '}
                              <span className="font-semibold text-slate-700 dark:text-slate-200">
                                {skill.app_display_name || skill.engine_id}
                              </span>
                            </p>
                          </div>
                        </div>

                        {isPending ? (
                          <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-amber-300 bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-900 dark:border-amber-800 dark:bg-amber-950/80 dark:text-amber-200">
                            <Clock className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400" />
                            Pending Review
                          </span>
                        ) : isApproved ? (
                          <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-emerald-300 bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-900 dark:border-emerald-800 dark:bg-emerald-950/80 dark:text-emerald-200">
                            <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600 dark:text-emerald-400" />
                            Approved & Shared
                          </span>
                        ) : (
                          <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-300">
                            Draft
                          </span>
                        )}
                      </div>

                      {/* Description */}
                      <p className="mt-4 text-sm leading-relaxed text-slate-600 dark:text-slate-300">
                        {skill.description || 'No description provided.'}
                      </p>

                      {/* 5-Stage Visual Workflow Stepper */}
                      <WorkflowStepper workflow={skill.workflow} />

                      {/* Governance & Share Request Details Box */}
                      <div className="mt-4 space-y-2 rounded-xl border border-slate-200/80 bg-slate-50/80 p-3.5 text-xs dark:border-slate-800 dark:bg-slate-950/60">
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <span className="inline-flex items-center gap-1.5 text-slate-500 dark:text-slate-400">
                            <UserCheck className="h-3.5 w-3.5 text-blue-500" />
                            Created By (Owner):
                          </span>
                          <span className="font-mono font-semibold text-slate-800 dark:text-slate-200">
                            {skill.owner_email || 'Unknown'}
                          </span>
                        </div>

                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <span className="inline-flex items-center gap-1.5 text-slate-500 dark:text-slate-400">
                            <ShieldAlert className="h-3.5 w-3.5 text-amber-500" />
                            GE State / Sharing Scope:
                          </span>
                          <span className="font-mono text-slate-700 dark:text-slate-300">
                            {skill.state} • {skill.sharing_scope} (
                            {skill.sharing_state})
                          </span>
                        </div>

                        {skill.iam_proposals.length > 0 && (
                          <div className="border-t border-slate-200/80 pt-2 dark:border-slate-800">
                            <p className="mb-1.5 flex items-center gap-1.5 font-semibold text-amber-800 dark:text-amber-300">
                              <Users className="h-3.5 w-3.5" />
                              Share Requested For:
                            </p>
                            <div className="space-y-1">
                              {skill.iam_proposals.map((prop) => (
                                <div
                                  key={prop.proposal_id}
                                  className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-amber-100/60 px-2.5 py-1.5 dark:bg-amber-950/40"
                                >
                                  <span className="font-mono font-semibold text-amber-950 dark:text-amber-200">
                                    {cleanPrincipal(prop.principal)}
                                  </span>
                                  <span className="text-[11px] text-amber-800 dark:text-amber-300">
                                    {prop.role.replace(
                                      'roles/discoveryengine.',
                                      '',
                                    )}{' '}
                                    • {prop.state} •{' '}
                                    {formatShortDate(prop.create_time)}
                                  </span>
                                </div>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Card Footer with InfoSec Approval Actions */}
                    <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 pt-4 dark:border-slate-800/80">
                      <span className="text-[11px] text-slate-400 dark:text-slate-500">
                        Updated {formatShortDate(skill.update_time)}
                      </span>

                      <div className="flex flex-wrap items-center gap-2.5">
                        {isPending && onApproveSkill && (
                          <button
                            type="button"
                            disabled={actionBusyId === skill.skill_id}
                            onClick={() =>
                              void handleApproveClick(skill.skill_id)
                            }
                            className="inline-flex items-center gap-1.5 rounded-xl bg-emerald-600 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-emerald-500 disabled:opacity-50"
                          >
                            <ShieldCheck
                              className="h-3.5 w-3.5"
                              aria-hidden="true"
                            />
                            Approve & Publish
                          </button>
                        )}

                        {isPending && onRejectSkill && (
                          <button
                            type="button"
                            disabled={actionBusyId === skill.skill_id}
                            onClick={() =>
                              void handleRejectClick(skill.skill_id)
                            }
                            className="inline-flex items-center gap-1.5 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-semibold text-red-700 transition hover:bg-red-100 dark:border-red-900/60 dark:bg-red-950/50 dark:text-red-300"
                          >
                            <XCircle
                              className="h-3.5 w-3.5"
                              aria-hidden="true"
                            />
                            Reject
                          </button>
                        )}

                        <button
                          type="button"
                          onClick={() => setSelectedSkill(skill)}
                          className="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-slate-800 dark:bg-blue-600 dark:hover:bg-blue-500"
                        >
                          <FileCode
                            className="h-3.5 w-3.5"
                            aria-hidden="true"
                          />
                          Inspect SKILL.md & Proposals
                        </button>
                      </div>
                    </div>
                  </article>
                );
              })}
            </div>
          )}
        </>
      )}

      {/* SKILL.md & Governance Detail Modal */}
      {selectedSkill && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={`Skill details for ${selectedSkill.display_name}`}
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 p-4 backdrop-blur-xs"
        >
          <div className="flex max-h-[88vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl dark:border-slate-800 dark:bg-slate-900">
            <div className="flex items-center justify-between border-b border-slate-200 px-6 py-4 dark:border-slate-800">
              <div>
                <div className="flex items-center gap-2.5">
                  <h3 className="text-lg font-bold text-slate-900 dark:text-white">
                    {selectedSkill.display_name}
                  </h3>
                  <span className="rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-semibold text-amber-800 dark:bg-amber-950 dark:text-amber-300">
                    {selectedSkill.review_status === 'PENDING_REVIEW'
                      ? 'Pending Review'
                      : selectedSkill.review_status}
                  </span>
                </div>
                <p className="mt-0.5 font-mono text-xs text-slate-500 dark:text-slate-400">
                  {selectedSkill.resource_name}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setSelectedSkill(null)}
                aria-label="Close skill details"
                className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-slate-600 dark:hover:bg-slate-800 dark:hover:text-slate-200"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="space-y-5 overflow-y-auto p-6">
              <WorkflowStepper workflow={selectedSkill.workflow} />

              <div className="grid gap-3 rounded-xl border border-slate-200 bg-slate-50 p-4 text-xs sm:grid-cols-2 dark:border-slate-800 dark:bg-slate-950">
                <div>
                  <p className="text-slate-400">Parent GE App</p>
                  <p className="mt-0.5 font-semibold text-slate-800 dark:text-slate-200">
                    {selectedSkill.app_display_name} ({selectedSkill.engine_id})
                  </p>
                </div>
                <div>
                  <p className="text-slate-400">Skill Owner</p>
                  <p className="mt-0.5 font-mono font-semibold text-slate-800 dark:text-slate-200">
                    {selectedSkill.owner_email || '—'}
                  </p>
                </div>
                <div className="sm:col-span-2">
                  <p className="flex items-center gap-1 text-slate-400">
                    <FolderGit2 className="h-3.5 w-3.5" />
                    Cloud Storage Artifact URI
                  </p>
                  <p className="mt-0.5 break-all font-mono text-[11px] text-slate-700 dark:text-slate-300">
                    {selectedSkill.gcs_uri || '—'}
                  </p>
                </div>
              </div>

              <div>
                <h4 className="mb-2 text-xs font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                  Skill Instruction (SKILL.md)
                </h4>
                <pre className="max-h-96 overflow-auto whitespace-pre-wrap rounded-xl border border-slate-200 bg-slate-950 p-4 font-mono text-xs leading-relaxed text-slate-100 dark:border-slate-800">
                  {selectedSkill.instruction ||
                    'No SKILL.md instruction found.'}
                </pre>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
