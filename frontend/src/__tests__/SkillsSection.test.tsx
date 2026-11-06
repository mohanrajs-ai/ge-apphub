import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { Sidebar } from '../components/Sidebar';
import { SkillsSection } from '../components/SkillsSection';
import { DiscoveredSkill } from '../types/catalog';

const MOCK_SKILLS: DiscoveredSkill[] = [
  {
    skill_id: 'service-desk-app-01:16453101121688192599',
    resource_name:
      'projects/720923281941/locations/global/collections/default_collection/engines/service-desk-app-01/assistants/default_assistant/agents/16453101121688192599',
    engine_id: 'service-desk-app-01',
    app_display_name: 'Gemini Service Desk App',
    display_name: 'daily-morning-summary',
    description:
      'Compiles a concise morning briefing synthesizing Outlook Calendar, Email, and Teams.',
    instruction: '# Daily Morning Summary\n\nStep 1: Fetch calendar.',
    gcs_uri: 'gs://bucket/daily-morning-summary/',
    owner_email: 'admin@mohanrajs.altostrat.com',
    state: 'DISABLED',
    sharing_scope: 'RESTRICTED',
    sharing_state: 'PENDING',
    has_active_iam_proposals: true,
    review_status: 'PENDING_REVIEW',
    iam_proposals: [
      {
        proposal_id: '8420372054855937333',
        principal: 'user:mohanraj@mohanrajs.altostrat.com',
        role: 'roles/discoveryengine.agentUser',
        state: 'ACTIVE',
        create_time: '2026-11-02T12:59:45.647329Z',
        expire_time: '2026-12-17T12:59:44.681804149Z',
      },
    ],
    shared_principals: ['user:admin@mohanrajs.altostrat.com'],
    subfiles: [{ file_name: 'SKILL.md', mime_type: 'text/markdown' }],
    create_time: '2026-10-31T12:08:33.345419Z',
    update_time: '2026-10-31T12:08:33.345419Z',
    workflow: {
      workflow_id: 'wf-service-desk-app-01-16453101121688192599',
      skill_id: 'service-desk-app-01:16453101121688192599',
      engine_id: 'service-desk-app-01',
      skill_display_name: 'daily-morning-summary',
      owner_email: 'admin@mohanrajs.altostrat.com',
      current_stage: 'AWAITING_INFOSEC_APPROVAL',
      status: 'AWAITING_APPROVAL',
      eval_score: 100,
      eval_status: 'PASSED',
      infosec_risk_level: 'LOW',
      infosec_status: 'PASSED',
      approval_status: 'PENDING',
      approved_by: '',
      approval_notes: '',
      registry_id: '',
      shared_in_ge: false,
      shared_principals: [],
    },
  },
];

describe('Sidebar and SkillsSection', () => {
  it('renders Apps, Skills, and Agents in Sidebar and triggers navigation', () => {
    const onSelect = vi.fn();
    render(
      <Sidebar
        activeSection="apps"
        onSelectSection={onSelect}
        appsCount={7}
        skillsCount={1}
        pendingSkillsCount={1}
      />,
    );

    expect(screen.getByText('Apps')).toBeInTheDocument();
    expect(screen.getByText('Skills')).toBeInTheDocument();
    expect(screen.getByText('Agents')).toBeInTheDocument();
    expect(
      screen.getByText('Pending Skill Share Requests'),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByText('Skills'));
    expect(onSelect).toHaveBeenCalledWith('skills');

    fireEvent.click(screen.getByText('Agents'));
    expect(onSelect).toHaveBeenCalledWith('agents');
  });

  it('renders Pending Review tab with 5-stage workflow, InfoSec approval, and SKILL.md modal', () => {
    const onApprove = vi.fn();
    render(
      <SkillsSection
        skills={MOCK_SKILLS}
        pendingReviewCount={1}
        approvedCount={0}
        loading={false}
        onApproveSkill={onApprove}
      />,
    );

    expect(screen.getByText('daily-morning-summary')).toBeInTheDocument();
    expect(screen.getByText('1. Skill Eval Agent')).toBeInTheDocument();
    expect(screen.getByText('2. InfoSec Agent')).toBeInTheDocument();
    expect(screen.getByText('3. InfoSec Approval')).toBeInTheDocument();
    expect(screen.getByText('4. Skill Registry')).toBeInTheDocument();
    expect(screen.getByText('5. Share to App')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Approve & Publish'));
    expect(onApprove).toHaveBeenCalledWith(
      'service-desk-app-01:16453101121688192599',
    );

    fireEvent.click(screen.getByText('Inspect SKILL.md & Proposals'));
    expect(
      screen.getByRole('dialog', {
        name: /Skill details for daily-morning-summary/i,
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/# Daily Morning Summary/i),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByLabelText('Close skill details'));

    fireEvent.click(screen.getByRole('tab', { name: /Approved & Shared/i }));
    expect(
      screen.getByText(/No skills found in this view/i),
    ).toBeInTheDocument();
  });
});
