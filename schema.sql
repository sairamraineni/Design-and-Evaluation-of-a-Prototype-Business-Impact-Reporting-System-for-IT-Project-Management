-- ============================================================
-- Business-Impact Reporting System — Database Schema
-- Compatible with: SQLite 3.x | PostgreSQL 13+
-- ============================================================

-- ============================================================
-- 1. PROJECTS
-- Core project registry. Each row is one IT project.
-- ============================================================
CREATE TABLE IF NOT EXISTS projects (
    project_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    project_name    TEXT    NOT NULL,
    description     TEXT,
    start_date      DATE    NOT NULL,
    end_date        DATE,
    status          TEXT    NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'completed', 'on_hold', 'cancelled')),
    project_manager TEXT    NOT NULL,
    budget          REAL,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 2. TASKS
-- Granular work items within a project.
-- Stores both planned and actual dates for schedule analysis.
-- ============================================================
CREATE TABLE IF NOT EXISTS tasks (
    task_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    task_name       TEXT    NOT NULL,
    description     TEXT,
    planned_start   DATE    NOT NULL,
    planned_end     DATE    NOT NULL,
    actual_start    DATE,
    actual_end      DATE,
    completion_pct  REAL    DEFAULT 0.0
                    CHECK (completion_pct BETWEEN 0.0 AND 100.0),
    status          TEXT    DEFAULT 'not_started'
                    CHECK (status IN ('not_started', 'in_progress', 'completed', 'blocked')),
    milestone       INTEGER DEFAULT 0          -- 1 = this task is a milestone
);

-- ============================================================
-- 3. RESOURCES
-- People or teams that can be assigned to tasks.
-- ============================================================
CREATE TABLE IF NOT EXISTS resources (
    resource_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    NOT NULL,
    role            TEXT    NOT NULL,
    department      TEXT,
    hourly_rate     REAL    DEFAULT 0.0,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 4. TASK_RESOURCE_USAGE
-- Junction table: which resource worked on which task,
-- and for how many hours (planned vs actual).
-- ============================================================
CREATE TABLE IF NOT EXISTS task_resource_usage (
    usage_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id         INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    resource_id     INTEGER NOT NULL REFERENCES resources(resource_id),
    hours_planned   REAL    DEFAULT 0.0,
    hours_actual    REAL    DEFAULT 0.0,
    cost_actual     REAL    DEFAULT 0.0    -- computed by app layer: hours_actual * hourly_rate
);

-- ============================================================
-- 5. RISKS
-- Risk register linked to a project.
-- ============================================================
CREATE TABLE IF NOT EXISTS risks (
    risk_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    description     TEXT    NOT NULL,
    probability     TEXT    DEFAULT 'medium'
                    CHECK (probability IN ('low', 'medium', 'high')),
    impact          TEXT    DEFAULT 'medium'
                    CHECK (impact IN ('low', 'medium', 'high')),
    status          TEXT    DEFAULT 'open'
                    CHECK (status IN ('open', 'mitigated', 'closed')),
    identified_date DATE    DEFAULT CURRENT_DATE,
    mitigation_plan TEXT
);

-- ============================================================
-- 6. TECHNICAL_METRICS
-- Raw technical performance measurements captured over time.
-- Examples: bug count, test coverage %, deployment frequency.
-- ============================================================
CREATE TABLE IF NOT EXISTS technical_metrics (
    metric_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    metric_name     TEXT    NOT NULL,
    metric_value    REAL    NOT NULL,
    unit            TEXT,               -- e.g. 'percent', 'hours', 'count'
    recorded_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    source          TEXT                -- e.g. 'Jira', 'CI/CD pipeline', 'manual'
);

-- ============================================================
-- 7. KPIS  (Business Performance Indicators)
-- The business-facing outcomes. These are predefined and
-- stable — they do not change per project.
-- ============================================================
CREATE TABLE IF NOT EXISTS kpis (
    kpi_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    kpi_name        TEXT    NOT NULL UNIQUE,
    description     TEXT,
    category        TEXT    NOT NULL,   -- e.g. 'cost', 'quality', 'schedule', 'risk'
    unit            TEXT,               -- e.g. 'percent', 'GBP', 'ratio'
    target_value    REAL,
    higher_is_better INTEGER DEFAULT 1  -- 1 = higher is better, 0 = lower is better
);

-- ============================================================
-- 8. METRIC_KPI_MAPPING
-- Rule-based mapping: which technical metrics feed which KPI,
-- what formula to apply, and what weight each metric carries.
-- ============================================================
CREATE TABLE IF NOT EXISTS metric_kpi_mapping (
    mapping_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    metric_name     TEXT    NOT NULL,   -- matches technical_metrics.metric_name
    kpi_id          INTEGER NOT NULL REFERENCES kpis(kpi_id),
    formula         TEXT    NOT NULL,   -- e.g. 'value / target * 100'
    weight          REAL    DEFAULT 1.0 -- for weighted aggregation
                    CHECK (weight > 0),
    description     TEXT
);

-- ============================================================
-- 9. REPORTS
-- Metadata for each generated report run.
-- ============================================================
CREATE TABLE IF NOT EXISTS reports (
    report_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      INTEGER NOT NULL REFERENCES projects(project_id),
    report_type     TEXT    NOT NULL DEFAULT 'business_impact'
                    CHECK (report_type IN ('business_impact', 'technical', 'executive')),
    generated_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    generated_by    TEXT,
    notes           TEXT
);

-- ============================================================
-- 10. REPORT_KPI_VALUES
-- The computed KPI values for each report run.
-- One row per KPI per report.
-- ============================================================
CREATE TABLE IF NOT EXISTS report_kpi_values (
    value_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id       INTEGER NOT NULL REFERENCES reports(report_id) ON DELETE CASCADE,
    kpi_id          INTEGER NOT NULL REFERENCES kpis(kpi_id),
    computed_value  REAL,
    target_value    REAL,
    status          TEXT    DEFAULT 'on_track'
                    CHECK (status IN ('on_track', 'at_risk', 'off_track')),
    notes           TEXT
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_tasks_project       ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_usage_task          ON task_resource_usage(task_id);
CREATE INDEX IF NOT EXISTS idx_usage_resource      ON task_resource_usage(resource_id);
CREATE INDEX IF NOT EXISTS idx_risks_project       ON risks(project_id);
CREATE INDEX IF NOT EXISTS idx_metrics_project     ON technical_metrics(project_id);
CREATE INDEX IF NOT EXISTS idx_metrics_name        ON technical_metrics(metric_name);
CREATE INDEX IF NOT EXISTS idx_mapping_metric      ON metric_kpi_mapping(metric_name);
CREATE INDEX IF NOT EXISTS idx_mapping_kpi         ON metric_kpi_mapping(kpi_id);
CREATE INDEX IF NOT EXISTS idx_reports_project     ON reports(project_id);
CREATE INDEX IF NOT EXISTS idx_report_kpi_report   ON report_kpi_values(report_id);

-- ============================================================
-- SEED DATA — KPIs (predefined business indicators)
-- ============================================================
INSERT OR IGNORE INTO kpis (kpi_name, description, category, unit, target_value, higher_is_better) VALUES
  ('Schedule Performance Index',  'Ratio of earned to planned schedule value',       'schedule', 'ratio',   1.0,  1),
  ('Budget Utilisation',          'Actual cost vs planned budget',                   'cost',     'percent', 100.0, 0),
  ('Resource Efficiency',         'Actual vs planned hours ratio',                   'cost',     'ratio',   1.0,  0),
  ('Risk Exposure Score',         'Weighted count of open high-impact risks',        'risk',     'score',   0.0,  0),
  ('Defect Resolution Rate',      'Percentage of bugs resolved within target SLA',   'quality',  'percent', 95.0, 1),
  ('Test Coverage',               'Percentage of codebase covered by tests',         'quality',  'percent', 80.0, 1),
  ('Milestone Completion Rate',   'Milestones completed on time vs total planned',   'schedule', 'percent', 100.0, 1),
  ('Stakeholder Value Delivery',  'Business objectives met as a percentage',         'value',    'percent', 100.0, 1);

-- ============================================================
-- SEED DATA — Metric-to-KPI Mapping Rules
-- ============================================================
INSERT OR IGNORE INTO metric_kpi_mapping (metric_name, kpi_id, formula, weight, description) VALUES
  ('schedule_variance_days',  1, '1 + (value / planned_duration)',  1.0, 'Negative variance = behind schedule'),
  ('budget_spent_pct',        2, 'value',                           1.0, 'Direct mapping'),
  ('hours_actual',            3, 'hours_actual / hours_planned',    1.0, 'Efficiency ratio'),
  ('open_high_risks',         4, 'value * 3',                       1.0, 'High risks weighted x3'),
  ('open_medium_risks',       4, 'value * 1',                       0.5, 'Medium risks weighted x1'),
  ('bugs_resolved_on_time',   5, '(value / total_bugs) * 100',      1.0, 'Resolution rate percent'),
  ('test_coverage_pct',       6, 'value',                           1.0, 'Direct mapping'),
  ('milestones_on_time',      7, '(value / total_milestones) * 100',1.0, 'On-time milestone rate');

-- ============================================================
-- SEED DATA — Sample Project
-- ============================================================
INSERT OR IGNORE INTO projects (project_name, description, start_date, end_date, status, project_manager, budget) VALUES
  ('CRM Platform Upgrade', 'Upgrade the legacy CRM to a cloud-based solution', '2025-01-15', '2025-06-30', 'active', 'Jane Smith', 150000.00);

INSERT OR IGNORE INTO resources (name, role, department, hourly_rate) VALUES
  ('Alice Nguyen',  'Backend Developer', 'Engineering', 75.00),
  ('Bob Patel',     'QA Engineer',       'Engineering', 60.00),
  ('Carol Wright',  'Business Analyst',  'PMO',         65.00);

INSERT OR IGNORE INTO tasks (project_id, task_name, planned_start, planned_end, actual_start, completion_pct, status, milestone) VALUES
  (1, 'Requirements Gathering', '2025-01-15', '2025-02-01', '2025-01-15', 100.0, 'completed', 0),
  (1, 'System Design',          '2025-02-02', '2025-02-28', '2025-02-03', 100.0, 'completed', 1),
  (1, 'Backend Development',    '2025-03-01', '2025-04-30', '2025-03-01',  65.0, 'in_progress', 0),
  (1, 'QA & Testing',           '2025-04-15', '2025-05-31', NULL,           0.0, 'not_started', 0),
  (1, 'User Acceptance Testing','2025-06-01', '2025-06-20', NULL,           0.0, 'not_started', 1),
  (1, 'Go Live',                '2025-06-30', '2025-06-30', NULL,           0.0, 'not_started', 1);

INSERT OR IGNORE INTO risks (project_id, description, probability, impact, status, mitigation_plan) VALUES
  (1, 'Legacy data migration may cause delays', 'high',   'high',   'open',      'Allocate dedicated migration sprint'),
  (1, 'Third-party API availability',           'medium', 'medium', 'mitigated', 'Use mock APIs during development'),
  (1, 'Scope creep from stakeholders',          'medium', 'high',   'open',      'Strict change control process');

INSERT OR IGNORE INTO technical_metrics (project_id, metric_name, metric_value, unit, source) VALUES
  (1, 'budget_spent_pct',       43.0,  'percent', 'Finance System'),
  (1, 'test_coverage_pct',      67.0,  'percent', 'CI Pipeline'),
  (1, 'schedule_variance_days', -3.0,  'days',    'Jira'),
  (1, 'open_high_risks',         2.0,  'count',   'Risk Register'),
  (1, 'open_medium_risks',       1.0,  'count',   'Risk Register'),
  (1, 'milestones_on_time',      1.0,  'count',   'Jira'),
  (1, 'bugs_resolved_on_time',  12.0,  'count',   'Jira');

-- ============================================================
-- USEFUL VIEWS
-- ============================================================

-- Project health summary (one row per project)
CREATE VIEW IF NOT EXISTS vw_project_health AS
SELECT
    p.project_id,
    p.project_name,
    p.project_manager,
    p.status,
    COUNT(DISTINCT t.task_id)                               AS total_tasks,
    ROUND(AVG(t.completion_pct), 1)                         AS avg_completion_pct,
    COUNT(DISTINCT r.risk_id) FILTER (WHERE r.status='open' AND r.impact='high') AS open_high_risks,
    COUNT(DISTINCT t.task_id) FILTER (WHERE t.milestone=1 AND t.status='completed') AS milestones_done
FROM projects p
LEFT JOIN tasks t    ON t.project_id = p.project_id
LEFT JOIN risks r    ON r.project_id = p.project_id
GROUP BY p.project_id;

-- Resource utilisation per task
CREATE VIEW IF NOT EXISTS vw_resource_utilisation AS
SELECT
    p.project_name,
    t.task_name,
    res.name            AS resource_name,
    res.role,
    u.hours_planned,
    u.hours_actual,
    ROUND(u.hours_actual / NULLIF(u.hours_planned, 0), 2)   AS utilisation_ratio,
    ROUND(u.hours_actual * res.hourly_rate, 2)              AS actual_cost
FROM task_resource_usage u
JOIN tasks    t   ON t.task_id    = u.task_id
JOIN projects p   ON p.project_id = t.project_id
JOIN resources res ON res.resource_id = u.resource_id;

-- Latest KPI values per project
CREATE VIEW IF NOT EXISTS vw_latest_kpi_values AS
SELECT
    p.project_name,
    k.kpi_name,
    k.category,
    rkv.computed_value,
    rkv.target_value,
    rkv.status,
    r.generated_at
FROM report_kpi_values rkv
JOIN reports  r ON r.report_id  = rkv.report_id
JOIN kpis     k ON k.kpi_id     = rkv.kpi_id
JOIN projects p ON p.project_id = r.project_id
WHERE r.generated_at = (
    SELECT MAX(r2.generated_at) FROM reports r2 WHERE r2.project_id = r.project_id
);
