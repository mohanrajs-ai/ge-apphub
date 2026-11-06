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

  it('renders Pending Review tab with skill details and SKILL.md modal', () => {
    render(
      <SkillsSection
        skills={MOCK_SKILLS}
        pendingReviewCount={1}
        approvedCount={0}
        loading={false}
      />,
    );

    expect(screen.getByText('daily-morning-summary')).toBeInTheDocument();
    expect(
      screen.getByText('admin@mohanrajs.altostrat.com'),
    ).toBeInTheDocument();
    expect(
      screen.getByText('mohanraj@mohanrajs.altostrat.com'),
    ).toBeInTheDocument();

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
